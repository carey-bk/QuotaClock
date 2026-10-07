import AppKit
import SwiftUI
import UserNotifications
import QuotaCore

@MainActor final class ResetNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ResetNotifications()
    @Published private(set) var enabled: Bool
    @Published private(set) var authorized = false
    @Published private(set) var requesting = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var failed = false
    private var detector: CodexResetDetector
    private let defaults = UserDefaults.standard
    private let stateKey = "codex.resetNotificationState.v1"
    private var generation = 0
    private override init() {
        enabled = UserDefaults.standard.bool(forKey: "codex.resetNotifications.enabled")
        detector = UserDefaults.standard.data(forKey: "codex.resetNotificationState.v1")
            .flatMap { try? JSONDecoder().decode(CodexResetDetector.self, from: $0) } ?? CodexResetDetector()
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        permissionDenied = settings.authorizationStatus == .denied
    }
    func setEnabled(_ value: Bool) {
        generation += 1
        enabled = value
        defaults.set(value, forKey: "codex.resetNotifications.enabled")
        detector = CodexResetDetector() // No retroactive notifications when enabling.
        defaults.removeObject(forKey: stateKey)
        failed = false
        if !value {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        Task { await requestPermission() }
    }
    func requestPermission() async {
        guard !requesting else { return }
        requesting = true
        failed = false
        defer { requesting = false }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { failed = true }
        await refreshPermission()
    }
    func consume(_ snapshot: QuotaSnapshot, language: AppLanguage) {
        guard enabled else { return }
        let events = detector.consume(snapshot)
        if let data = try? JSONEncoder().encode(detector) { defaults.set(data, forKey: stateKey) }
        let epoch = generation
        for event in events {
            let name = snapshot.providers.first { $0.id == event.accountID }?.account?.signature ?? "Codex"
            let content = UNMutableNotificationContent()
            content.title = AppText.value(event.weekly ? "Codex weekly limit reset" : "Codex 5-hour limit reset", language)
            content.body = String(format: AppText.value("%@ · Quota window has reset.", language), name)
            content.sound = .default
            Task {
                await refreshPermission()
                guard enabled, generation == epoch, authorized else { return }
                do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.identifier, content: content, trigger: nil)) }
                catch { failed = true }
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { self.enabled ? [.banner, .sound] : [] }
    }
}

struct ResetNotificationSettings: View {
    let language: AppLanguage
    var preview = false
    var body: some View {
        if preview {
            Text(AppText.value("Notify when Codex limits reset", language))
        } else { ResetNotificationControls(language: language) }
    }
}
private struct ResetNotificationControls: View {
    let language: AppLanguage
    @ObservedObject private var notifications = ResetNotifications.shared
    @Environment(\.scenePhase) private var scenePhase
    private func t(_ key: String) -> String { AppText.value(key, language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(t("Notify when Codex limits reset"), isOn: Binding(get: { notifications.enabled }, set: notifications.setEnabled))
                .disabled(notifications.requesting)
            Text(t("Alerts for 5-hour and weekly resets detected while QuotaClock is running."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if notifications.enabled && !notifications.authorized {
                if notifications.permissionDenied {
                    Text(t("Notifications are disabled in System Settings.")).font(.caption)
                    Button(t("Open Notification Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                } else {
                    Button(t("Allow Notifications…")) { Task { await notifications.requestPermission() } }
                        .disabled(notifications.requesting)
                }
            }
            if notifications.failed { Text(t("Notification request failed. Please try again.")).font(.caption).foregroundStyle(.secondary) }
        }
        .task { await notifications.refreshPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await notifications.refreshPermission() } }
        }
    }
}

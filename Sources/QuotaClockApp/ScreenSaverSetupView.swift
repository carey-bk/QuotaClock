import AppKit
import SwiftUI
import QuotaCore

/// System selection is read-only. Only the user's explicit auto-start toggle changes idleTime.
@MainActor final class ScreenSaverSystemController: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var selected: Bool?
    @Published private(set) var idleSeconds: Int?
    @Published var error: String?
    let preview: Bool
    private let domain: CFString
    private let defaults: UserDefaults
    var autoStart: Bool { (idleSeconds ?? 0) > 0 }
    init(preview: Bool = false, domain: String = "com.apple.screensaver", defaults: UserDefaults = .standard) {
        self.preview = preview; self.domain = domain as CFString; self.defaults = defaults
        refresh()
    }
    func refresh() {
        if preview { installed = true; selected = false; if idleSeconds == nil { idleSeconds = 300 }; return }
        installed = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/QuotaClock.saver").path,
                     "/Library/Screen Savers/QuotaClock.saver"].contains { FileManager.default.fileExists(atPath: $0) }
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        idleSeconds = (CFPreferencesCopyValue("idleTime" as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? NSNumber)?.intValue
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        if let data = try? Data(contentsOf: path) { selected = ScreenSaverSelection.isQuotaClock(in: data) }
        else { selected = nil }
    }
    func setAutoStart(_ enabled: Bool) {
        error = nil
        let previous = idleSeconds ?? 0
        if !enabled && previous > 0 && !preview { defaults.set(previous, forKey: "screenSaver.previousIdleSeconds") }
        let saved = defaults.integer(forKey: "screenSaver.previousIdleSeconds")
        let next = enabled ? (previous > 0 ? previous : (saved > 0 ? saved : 300)) : 0
        if preview { idleSeconds = next; return }
        guard !CFPreferencesAppValueIsForced("idleTime" as CFString, domain) else {
            error = "Screen saver timing is managed by your organization."; return
        }
        CFPreferencesSetValue("idleTime" as CFString, NSNumber(value: next), domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        let written = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        refresh()
        if !written || idleSeconds != next { error = "Could not change screen saver timing. Open System Settings to try again." }
    }
    func openSettings() {
        guard !preview else { error = "Preview only. System settings were not changed."; return }
        // macOS 26+ presents Screen Saver inside Wallpaper; older systems retain the dedicated pane.
        let address: String
        if #available(macOS 26.0, *) { address = "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension" }
        else { address = "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension" }
        if !NSWorkspace.shared.open(URL(string: address)!) {
            error = "Could not open System Settings. Open Screen Saver settings manually."
        }
    }
}

struct ScreenSaverSetupView: View {
    let language: AppLanguage
    var compact = false
    @StateObject private var system: ScreenSaverSystemController
    init(language: AppLanguage, preview: Bool = false, compact: Bool = false) {
        self.language = language; self.compact = compact
        _system = StateObject(wrappedValue: ScreenSaverSystemController(preview: preview))
    }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if !compact {
                Toggle(t("Automatically start screen saver"), isOn: Binding(get: { system.autoStart }, set: system.setAutoStart))
                    .disabled(system.idleSeconds == nil)
                Text(t("Controls automatic screen saver startup for this Mac. Turning it off saves the waiting time; turning it on restores it (5 minutes if none was saved). Choose QuotaClock separately in System Settings."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            HStack(spacing: 8) {
                Image(systemName: system.selected == true ? "checkmark.circle.fill" : "display")
                    .foregroundStyle(system.selected == true ? Color.green : Color.secondary)
                Text(t(system.selected == true ? "QuotaClock is selected in macOS" : system.installed ? "Select QuotaClock in macOS" : "Install QuotaClock.saver first"))
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
            }
            Text(t(system.installed
                ? "Open Screen Saver in System Settings, choose Custom, then QuotaClock. Installation alone does not select it."
                : "Double-click QuotaClock.saver in the installer, then select QuotaClock in macOS Screen Saver settings."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(t("Open Screen Saver Settings"), action: system.openSettings).controlSize(compact ? .small : .regular)
            if let error = system.error { Text(t(error)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .onAppear { system.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in system.refresh() }
    }
}

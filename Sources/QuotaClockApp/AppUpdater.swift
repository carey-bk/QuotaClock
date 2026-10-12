import AppKit
import Combine
import SwiftUI
import QuotaCore
#if !ONBOARDING_PREVIEW
import Sparkle
#endif

/// One updater for the app lifetime. Quota polling never starts update checks.
@MainActor final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var availableVersion: String?
    var hasAvailableUpdate: Bool { availableVersion != nil }
    private static let availableVersionKey = "updater.availableVersion"
    @Published var automaticallyChecks = true {
        didSet {
            #if !ONBOARDING_PREVIEW
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
            #endif
        }
    }
    #if !ONBOARDING_PREVIEW
    private var controller: SPUStandardUpdaterController!
    private let versionComparison = ReleaseVersionComparison()
    private var manualCheck = false
    private var noUpdate = false
    private var foundVersion: String?
    private var pendingManualAlert: (NSAlert, Bool)?
    @Published private(set) var updateStatus: String?
    private var observations: Set<AnyCancellable> = []
    #endif

    private override init() {
        super.init()
        #if !ONBOARDING_PREVIEW
        // Defaults apply only when the user has not already chosen a preference.
        UserDefaults.standard.register(defaults: ["SUEnableAutomaticChecks": true])
        if let saved = UserDefaults.standard.string(forKey: Self.availableVersionKey),
           let remote = AppVersion(saved), let current = AppVersion(AppVersion.display()), remote > current {
            availableVersion = remote.display
        } else {
            UserDefaults.standard.removeObject(forKey: Self.availableVersionKey)
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecks = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.sessionInProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                if !active { self?.presentPendingManualResult() }
            }
            .store(in: &observations)
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        #if !ONBOARDING_PREVIEW
        if controller.updater.sessionInProgress {
            controller.checkForUpdates(nil)
            return
        }
        manualCheck = true
        foundVersion = nil
        noUpdate = false
        controller.updater.checkForUpdateInformation()
        #endif
    }

    func showAvailableUpdate() {
        #if !ONBOARDING_PREVIEW
        controller.checkForUpdates(nil)
        #endif
    }

    var bundledScreenSaver: URL? {
        Bundle.main.url(forResource: "QuotaClock", withExtension: "saver")
    }
    func installScreenSaver() {
        if let url = bundledScreenSaver { NSWorkspace.shared.open(url) }
    }
}

struct AppUpdateSettings: View {
    @ObservedObject private var updater = AppUpdater.shared
    let language: AppLanguage
    var includeScreenSaver = true
    private func t(_ key: String) -> String { AppText.value(key, language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(t("Check for Updates…")) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            #if !ONBOARDING_PREVIEW
            if let status = updater.updateStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
            #endif
            Toggle(t("Automatically check for updates"), isOn: $updater.automaticallyChecks)
            Text(t("Checks once a day. Downloads begin only after you confirm."))
                .font(.caption).foregroundStyle(.secondary)
            if includeScreenSaver {
            Divider()
            Button(t("Install or Update Screen Saver…")) { updater.installScreenSaver() }
                .disabled(updater.bundledScreenSaver == nil)
            Text(t("App updates include the widget. Update the screen saver separately using this button."))
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct AppUpdateBanner: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        if let version = updater.availableVersion {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现新版本 \(version)").font(.headline)
                    Text("查看更新内容后，可选择下载并安装。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("查看更新") { updater.showAvailableUpdate() }.buttonStyle(.borderedProminent)
            }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AppUpdateCommands: Commands {
    @ObservedObject private var updater = AppUpdater.shared
    let language: AppLanguage
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 QuotaClock") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationVersion: AppVersion.display(), .version: ""
                ])
            }
        }
        CommandGroup(after: .appInfo) {
            Button(AppText.value("Check for Updates…", language)) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

#if !ONBOARDING_PREVIEW
extension AppUpdater: SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    func versionComparator(for updater: SPUUpdater) -> (any SUVersionComparison)? { versionComparison }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) { versionComparison.load(appcast.items) }
    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        versionComparison.best(in: appcast)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundVersion = AppVersion(item.displayVersionString)?.display
        availableVersion = foundVersion
        UserDefaults.standard.set(availableVersion, forKey: Self.availableVersionKey)
        updateStatus = foundVersion.map { "发现新版本 \($0)" }
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        noUpdate = true
        availableVersion = nil
        UserDefaults.standard.removeObject(forKey: Self.availableVersionKey)
        updateStatus = "当前已是最新版本 · \(AppVersion.display())"
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard manualCheck else { return }
        manualCheck = false
        let alert = NSAlert()
        if let version = foundVersion {
            alert.messageText = "发现新版本 \(version)"
            alert.informativeText = "查看更新内容后，可选择下载并安装。"
            alert.addButton(withTitle: "查看更新")
            alert.addButton(withTitle: "稍后")
        } else if error != nil, !noUpdate {
            alert.messageText = "检查更新失败"
            alert.informativeText = "请检查网络连接后重试。"
            alert.addButton(withTitle: "好")
        } else {
            alert.messageText = "当前已是最新版本 · \(AppVersion.display())"
            alert.addButton(withTitle: "好")
        }
        updateStatus = alert.messageText
        // Sparkle calls this delegate before it releases its active session.
        // A nested modal run loop here can otherwise start a second check too early.
        pendingManualAlert = (alert, foundVersion != nil)
        presentPendingManualResult()
    }
    private func presentPendingManualResult() {
        guard !controller.updater.sessionInProgress, pendingManualAlert != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.controller.updater.sessionInProgress,
                  let (alert, hasUpdate) = self.pendingManualAlert else { return }
            self.pendingManualAlert = nil
            if alert.runModal() == .alertFirstButtonReturn, hasUpdate {
                self.showAvailableUpdate()
            }
        }
    }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        self.updater(controller.updater, didFindValidUpdate: update)
    }
}
#endif

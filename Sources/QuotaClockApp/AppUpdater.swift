import AppKit
import Combine
import SwiftUI
import QuotaCore
#if !ONBOARDING_PREVIEW
import Sparkle
#endif

/// One updater for the app lifetime. Quota polling never starts update checks.
@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet {
            #if !ONBOARDING_PREVIEW
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
            #endif
        }
    }
    #if !ONBOARDING_PREVIEW
    private let controller: SPUStandardUpdaterController
    private var observations: Set<AnyCancellable> = []
    #endif

    private init() {
        #if !ONBOARDING_PREVIEW
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecks = $0 }
            .store(in: &observations)
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
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
    private func t(_ key: String) -> String { AppText.value(key, language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(t("Check for Updates…")) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Toggle(t("Automatically check for updates"), isOn: $updater.automaticallyChecks)
            Text(t("Checks once a day. Downloads begin only after you confirm."))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button(t("Install or Update Screen Saver…")) { updater.installScreenSaver() }
                .disabled(updater.bundledScreenSaver == nil)
            Text(t("App updates include the widget. Update the screen saver separately using this button."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AppUpdateCommands: Commands {
    @ObservedObject private var updater = AppUpdater.shared
    let language: AppLanguage
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(AppText.value("Check for Updates…", language)) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

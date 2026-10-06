import SwiftUI
import WidgetKit
import QuotaCore
import OSLog

@MainActor final class SnapshotController: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var status = "Starting…"
    @Published var widgetStatus = "Widget configuration not checked."
    @Published var error: String?
    @Published var refreshing = false
    @Published var customAPIs: [GenericAPIConfiguration] = []
    @Published var validatingAPI = false
    @Published var apiFeedback: String?
    @Published var widgetRegistered: Bool?
    @Published var widgetInstances: Int?
    let usageStore = ObservedUsageStore()
    let apiRegistry = GenericAPIRegistry()
    let codexAccounts = CodexAccountStore()
    @Published var accounts: [ProviderAccount] = []
    @Published var currentCodexIdentity: String?
    var currentCodexCredentialRevision: String?
    var accountReloadTask: Task<Void, Never>?
    @Published var accountFeedback: String?
    @Published var providerSetup = ProviderSetupState()
    @Published var signingIn = false
    @Published var switchingAccountID: UUID?
    @Published var accountSwitchStage: String?
    @Published var accountSwitchFeedback: String? {
        didSet {
            feedbackDismissTask?.cancel()
            guard accountSwitchFeedback != nil else { return }
            feedbackDismissTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.accountSwitchFeedback = nil
            }
        }
    }
    private var feedbackDismissTask: Task<Void, Never>?
    @Published var menuAccountChooserOpen = false
    @Published var menuPresentationID = 0
    @Published var menuCardViewportHeight: CGFloat = 182
    var signInRequestID: UUID?
    @Published var signInPrompt: CodexSignInPrompt?
    var signInTask: Task<Void, Never>?

    var productDefinitions: [ProductDescriptor] { ProviderCatalog.products + customAPIs.map(\.descriptor) + accounts.map(\.descriptor) }
    func providerBaseName(_ id: String) -> String {
        if let account = accounts.first(where: { $0.sourceID == id }) { return ProviderCatalog.name(account.providerID) }
        return customAPIs.first { $0.providerID == id }?.name ?? ProviderCatalog.name(id)
    }
    func providerNickname(_ id: String) -> String? {
        let value = accounts.first { $0.sourceID == id }?.signature ?? platform.preference(id).nickname
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }
    func providerName(_ id: String) -> String {
        providerBaseName(id) + (providerNickname(id).map { " " + $0 } ?? "")
    }
    func saveNickname(_ value: String, for id: String) {
        guard value.isEmpty || ProviderAccount.validSignature(value) else { return }
        var next = platform, preference = next.preference(id)
        preference.nickname = value.isEmpty ? nil : value; next.display[id] = preference; savePlatform(next)
    }
    @Published var platform: PlatformPreferences
    @Published var preferences: AmbientPreferences
    let onboardingPreview: Bool
    var previewReduceMotion = false
    #if ONBOARDING_PREVIEW
    var previewSettingsSection: String?
    var previewShowDiagnostics = false
    #endif
    var coordinator: ProviderRefreshCoordinator?
    var openSettings: (() -> Void)?
    private var statusPanel: StatusPanelController?
    private var periodicTask: Task<Void, Never>?
    private var accountObservationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.quotaclock", category: "publisher")
    init(onboardingPreview: Bool = false) {
        self.onboardingPreview = onboardingPreview
        platform = onboardingPreview ? PlatformPreferences() : PlatformPreferences.load()
        preferences = onboardingPreview ? AmbientPreferences() : AmbientPreferences.read()
        if onboardingPreview { return } // No storage, Keychain, networking, timers or status item in previews.
        applyAppearance()
        applyLogo()
        // English is the default even when macOS itself uses Chinese.
        if (try? SnapshotLocations.saverPreferences()).map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            try? preferences.write()
        }
        UserDefaults(suiteName: SnapshotLocations.appGroup)?.set(preferences.effectiveWidgetLanguage.rawValue, forKey: "ui.widgetLanguage")
        try? platform.save()
        do { customAPIs = try apiRegistry.read() }
        catch { self.error = "Could not load custom API settings. Existing data was preserved." }
        load()
        inspectWidgets()
        statusPanel = StatusPanelController(model: self)
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                if let self {
                    if let coordinator = self.coordinator, await coordinator.hasAutomaticRefreshDue() { await self.refreshAll(manual: false) }
                } else { break }
            }
        }
        accountObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                if let self { await self.observeCurrentCodexAccount() } else { break }
            }
        }
    }
    deinit { periodicTask?.cancel(); accountObservationTask?.cancel() }
    private func applyAppearance() {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
        // Remove window-level overrides left by SwiftUI's preferredColorScheme.
        for window in NSApp.windows { window.appearance = nil }
    }
    func savePreferences(_ next: AmbientPreferences) {
        guard preferences != next else { return }
        if onboardingPreview { preferences = next; applyAppearance(); return }
        do { try next.write() }
        catch { self.error = "Could not save screen saver settings: \(error.localizedDescription)"; return }
        preferences = next
        applyAppearance()
        UserDefaults(suiteName: SnapshotLocations.appGroup)?.set(next.effectiveWidgetLanguage.rawValue, forKey: "ui.widgetLanguage")
        WidgetCenter.shared.reloadTimelines(ofKind: SnapshotLocations.widgetKind)
    }
    func enabled(_ providerID: String) -> Bool {
        if let account = accounts.first(where: { $0.sourceID == providerID }) { return platform.isProductEnabled(account.productID) }
        return productDefinitions.contains { $0.providerID == providerID && platform.isProductEnabled($0.id) }
    }
    var logoImage: NSImage {
        NSImage(named: platform.appLogo == .classic ? "LogoClassic" : "LogoGlow") ?? NSApp.applicationIconImage
    }
    func applyLogo() { NSApp.applicationIconImage = logoImage }
    func savePlatform(_ next: PlatformPreferences) {
        // SwiftUI can write the existing MenuBarExtra insertion value during reconciliation.
        // Publishing an unchanged value here creates a scene update feedback loop.
        guard next != platform else { return }
        if onboardingPreview { platform = next; applyLogo(); return }
        do { try next.save(); platform = next; applyLogo() }
        catch { self.error = "Could not save display settings"; return }
        Task {
            guard let coordinator else { return }
            do { show(try await coordinator.configure(next)) }
            catch { self.error = "Could not publish display settings" }
        }
    }
    func setProduct(_ id: String, enabled: Bool) {
        guard let definition = productDefinitions.first(where: { $0.id == id }), definition.supported else { return }
        var next = platform
        if enabled {
            next.enabledProducts.insert(id)
            if !(next.connectionOrder ?? []).contains(definition.providerID) {
                next.connectionOrder = (next.connectionOrder ?? []) + [definition.providerID]
            }
        } else { next.enabledProducts.remove(id) }
        savePlatform(next)
        if enabled { refreshProduct(id) }
    }
    func refreshProduct(_ id: String) {
        guard switchingAccountID == nil else { return }
        Task {
            guard let coordinator else { return }
            let controller = self
            await coordinator.refresh(productID: id) { next in await MainActor.run { controller.show(next) } }
        }
    }
    func saveKey(_ key: String, product: ProductDescriptor) {
        guard !onboardingPreview else { return }
        do {
            try ProductKeychain(.init(providerID: product.providerID, productID: product.id)).save(key)
            status = "API key saved in Keychain."
            Task {
                if let next = await coordinator?.invalidate(product.id) { show(next) }
                refreshProduct(product.id)
            }
        } catch { self.error = "Could not save API key" }
    }
    func removeKey(_ product: ProductDescriptor) {
        guard !onboardingPreview else { return }
        do {
            try ProductKeychain(.init(providerID: product.providerID, productID: product.id)).delete()
            status = "API key removed."
            Task {
                if let next = await coordinator?.invalidate(product.id) { show(next) }
                refreshProduct(product.id)
            }
        } catch { self.error = "Could not remove API key" }
    }
    func setCLIProfile(_ profile: String, productID: String) {
        guard !onboardingPreview else { return }
        UserDefaults.standard.set(profile, forKey: "profile.\(productID)")
        Task {
            if let next = await coordinator?.invalidate(productID) { show(next) }
        }
    }
    private func publisher() throws -> SnapshotPublisher {
        try SnapshotPublisher(shared: SnapshotStore(url: SnapshotLocations.shared()), display: SnapshotStore(url: SnapshotLocations.saverExport()))
    }
    func load() {
        do {
            let writer = try publisher()
            let existing = try? writer.shared.read()
            let safeExisting = existing?.providers.allSatisfy { $0.health != nil } == true ? existing : nil
            let adapters: [any ProductAdapter] = [
                LegacyProductAdapter(CodexProviderAdapter()), LegacyProductAdapter(ClaudeProviderAdapter()),
                DeepSeekProductAdapter(credential: { ProductKeychain(.init(providerID: "deepseek", productID: "deepseek.api")).read() }),
                GLMProvider(), KimiProvider(), KimiAPIProvider(), KimiAPIProvider(international: true),
                BailianProvider(product: "coding-plan", profile: { UserDefaults.standard.string(forKey: "profile.bailian.coding-plan") ?? "default" }),
                BailianProvider(product: "token-plan", profile: { UserDefaults.standard.string(forKey: "profile.bailian.token-plan") ?? "default" })] + customAPIs.map { GenericAPIProduct(configuration: $0, store: usageStore) }
            coordinator = ProviderRefreshCoordinator(adapters: adapters, publisher: writer, existing: safeExisting, preferences: platform)
            Task {
                guard let coordinator else { return }
                do {
                    try await enableAccountConnections()
                    await reloadAccounts()
                    try initializeDisplayOrdering()
                    show(try await coordinator.configure(platform))
                    status = safeExisting == nil ? "Real providers ready; Phase 0 mock data removed." : "Last-known snapshot loaded."
                    await refreshAll(manual: true)
                } catch { self.error = "Snapshot publication failed: \(error.localizedDescription)" }
            }
        } catch { self.error = "Storage unavailable: \(error.localizedDescription)" }
    }
    func show(_ next: QuotaSnapshot) {
        snapshot = next
        WidgetCenter.shared.reloadTimelines(ofKind: SnapshotLocations.widgetKind)
        logger.notice("Published revision=\(next.revision.uuidString, privacy: .public) providers=\(next.providers.count)")
    }
    func refreshAll(manual: Bool = true) async {
        guard let coordinator, !refreshing, switchingAccountID == nil else { return }
        refreshing = true
        defer { refreshing = false }
        await reloadAccounts()
        let controller = self
        await coordinator.refreshAll(manual: false) { next in
            await MainActor.run { controller.show(next) }
        }
        if let stale = try? await coordinator.markStale() { show(stale) }
        refreshing = false
        status = await coordinator.lastPublicationFailed() ? "Refresh finished; display export needs repair." : "Refresh finished."
    }
    func refresh(_ id: String) {
        guard let coordinator, !refreshing, switchingAccountID == nil else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            let controller = self
            await coordinator.refresh(providerID: id) { next in
                await MainActor.run { controller.show(next) }
            }
            refreshing = false
        }
    }
    func setEnabled(_ id: String, value: Bool) {
        var next = platform
        let definitions = productDefinitions.filter { $0.providerID == id && $0.supported }
        if value, let first = definitions.first { next.enabledProducts.insert(first.id) }
        else { for product in definitions { next.enabledProducts.remove(product.id) } }
        savePlatform(next)
        if value { refresh(id) }
    }
    func repairExport() {
        guard !onboardingPreview else { return }
        do { try publisher().repairDisplay(); status = "Display replica repaired." }
        catch { self.error = error.localizedDescription }
    }
    func copyDiagnostics() {
        let lines = ["QuotaClock diagnostics", "revision: \(snapshot?.revision.uuidString ?? "none")"] +
            (snapshot?.providers.flatMap { provider in
                provider.activeProducts.map { product in
                    "\(product.id): state=\(product.health?.state.rawValue ?? "unknown") meters=\(product.meters.count) reliability=\(product.meters.first?.reliability.rawValue ?? "unknown") lastSuccess=\(product.health?.lastSuccess?.ISO8601Format() ?? "none")"
                }
            } ?? [])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        status = "Sanitized diagnostics copied."
    }
    func inspectWidgets() {
        guard !onboardingPreview else { return }
        Task {
            let registered = await Task.detached { () -> Bool? in
                let process = Process(); let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                process.arguments = ["-m", "-i", "com.quotaclock.app.providerwidget"]
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let deadline = Date().addingTimeInterval(3)
                    while process.isRunning && Date() < deadline {
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    if process.isRunning { process.terminate(); return nil }
                    guard process.terminationStatus == 0 else { return nil }
                    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    return text.contains("com.quotaclock.app.providerwidget")
                } catch { return nil }
            }.value
            widgetRegistered = registered
        }
        WidgetCenter.shared.getCurrentConfigurations { result in
            Task { @MainActor in
                switch result {
                case .success(let widgets):
                    self.widgetInstances = widgets.filter { $0.kind == SnapshotLocations.widgetKind }.count
                    self.widgetStatus = "Configured QuotaClock widgets: \(widgets.filter { $0.kind == SnapshotLocations.widgetKind }.count)."
                case .failure: self.widgetStatus = "Widget configuration check failed."
                }
            }
        }
    }
}

#if !ONBOARDING_PREVIEW
@main struct QuotaClockApp: App {
    @StateObject private var model = SnapshotController()
    var body: some Scene {
        Window("QuotaClock — Settings", id: "settings") { QuotaClockRootView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 820, height: 600)
            .windowResizability(.contentMinSize)
        Window("Menu Bar Preview", id: "menu-preview") { FullMenuBarPreview(model: model) }
            .defaultSize(width: 780, height: 650).windowResizability(.contentSize)
        Window("Screen Saver Preview", id: "preview") { AmbientPreviewView(model: model).id(model.preferences.appearance) }
            .defaultSize(width: 900, height: 650)

    }
}

#endif

struct MenuSnapshotView: View {
    @ObservedObject var model: SnapshotController
    var showSettings: () -> Void
    var body: some View {
        MenuCardsView(choosingAccount: $model.menuAccountChooserOpen, snapshot: model.snapshot, language: model.preferences.effectiveMenuLanguage,
            refreshing: model.refreshing,
            hasConfiguredProviders: !model.connectedSources.isEmpty,
            accountOptions: model.accounts.filter { $0.providerID == "codex" }.map { $0.switchOption(currentIdentity: model.currentCodexIdentity) },
            switchingAccountID: model.switchingAccountID,
            switchingStatus: model.accountSwitchStage,
            switchFeedback: model.accountSwitchFeedback,
            accountActionsDisabled: model.signingIn,
            switchAccount: { id in
                if let account = model.accounts.first(where: { $0.id == id }) { model.switchCodexAccount(account) }
            },
            refresh: { Task { await model.refreshAll() } }, showSettings: showSettings,
            quit: { NSApp.terminate(nil) },
            cardViewportHeight: model.menuCardViewportHeight, presentationID: model.menuPresentationID,
            forceReducedMotion: model.previewReduceMotion, largeHero: model.platform.menuBarHeroLarge)
            // Reopening starts hidden, without a frame of the previous fully revealed cards.
            .id(model.menuPresentationID)
    }
}

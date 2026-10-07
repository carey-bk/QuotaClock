import AppKit
import ServiceManagement
import SwiftUI
import QuotaCore

private enum SettingsSection: String, CaseIterable, Hashable {
    case general = "General", providers = "AI Services", menuBar = "Menu Bar", screenSaver = "Screen Saver", about = "About"
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .providers: "square.stack.3d.up"
        case .menuBar: "menubar.rectangle"
        case .screenSaver: "display"
        case .about: "info.circle"
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: SnapshotController
    var reopenOnboarding: () -> Void = {}
    var startWithProviders = false
    @State private var selection: SettingsSection? = .general
    @State private var showingDiagnostics = false
    @State private var addingAPI = false
    @State private var removingAPI: GenericAPIConfiguration?
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var keys: [String: String] = [:]
    @Environment(\.openWindow) private var openWindow
    private var language: AppLanguage { model.preferences.language }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private func pref<T>(_ path: WritableKeyPath<AmbientPreferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: path] }, set: { value in
            var next = model.preferences; next[keyPath: path] = value; model.savePreferences(next)
        })
    }
    private func display<T>(_ id: String, _ path: WritableKeyPath<ProviderDisplayPreference, T>) -> Binding<T> {
        Binding(get: { model.platform.preference(id)[keyPath: path] }, set: { value in
            var next = model.platform; var p = next.preference(id); p[keyPath: path] = value
            next.display[id] = p; model.savePlatform(next)
        })
    }
    private var menuVisible: Binding<Bool> {
        Binding(get: { model.platform.showMenuBar }, set: { value in
            var next = model.platform; next.showMenuBar = value; model.savePlatform(next)
        })
    }
    private func providerDisplay<T>(_ path: WritableKeyPath<ProviderDisplayConfiguration, T>) -> Binding<T> {
        Binding(get: { model.displayConfiguration[keyPath: path] }, set: { value in
            var next = model.platform, configuration = model.displayConfiguration
            configuration[keyPath: path] = value
            next.providerDisplay = configuration
            model.savePlatform(next)
        })
    }
    private func logo(_ size: CGFloat) -> some View {
        AppLogoView(style: model.platform.appLogo, size: size)
    }
    private func brand(_ id: String, size: CGFloat = 32) -> some View {
        Group {
            if id == "kimi" || id == "glm" {
                Image(id == "kimi" ? "ProviderKimiApp" : "ProviderGLMApp").resizable().scaledToFit()
            } else if let asset = ProviderCatalog.providers.first(where: { $0.id == (model.accounts.first { $0.sourceID == id }?.providerID ?? id) })?.asset {
                Image(asset == "ProviderOpenAI" ? asset : asset + "Color").resizable().renderingMode(asset == "ProviderOpenAI" ? .template : .original).scaledToFit().foregroundStyle(.primary).padding(6)
            } else { Text(String(model.providerName(id).prefix(1))).font(.title3.weight(.semibold)) }
        }.frame(width: size, height: size)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
    var body: some View {
        NavigationSplitView {
            List {
                HStack(spacing: 8) { logo(34); BrandWordmark(size: 13) }.padding(.vertical, 10)
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Button { selection = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).foregroundStyle(selection == section ? QuotaClockColors.accent : Color.secondary).frame(width: 20)
                            Text(t(section.rawValue)).foregroundStyle(Color.primary)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).padding(.horizontal, 8)
                            .background(selection == section ? QuotaClockColors.accentSelectedBackground : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == section ? .isSelected : [])
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
            }.listStyle(.sidebar).font(.system(size: 13))
                .navigationSplitViewColumnWidth(min: 165, ideal: SettingsTokens.sidebarWidth, max: 180)
                .scrollContentBackground(.hidden)
                .background { SettingsSidebarMaterial().ignoresSafeArea(.container, edges: .top) }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsTokens.sectionGap) {
                    switch selection ?? .general {
                    case .general: general
                    case .providers: providers
                    case .menuBar: menuBar
                    case .screenSaver: saver
                    case .about: about
                    }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: SettingsTokens.contentWidth, alignment: .leading)
                    .padding(.horizontal, SettingsTokens.pageHorizontalPadding).padding(.vertical, SettingsTokens.pageTopPadding).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(selection)
            .navigationTitle(t((selection ?? .general).rawValue))
            .onAppear { model.openSettings = { openWindow(id: "settings") } }
        }.font(.system(size: 13))
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { heading("Diagnostics"); Spacer(); Button(t("Done")) { showingDiagnostics = false }.keyboardShortcut(.cancelAction) }
                ScrollView { diagnostics.frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(width: 520, height: 480)
        }
        .onAppear {
            if startWithProviders { selection = .providers }
            #if ONBOARDING_PREVIEW
            if let raw = model.previewSettingsSection { selection = SettingsSection(rawValue: raw) }
            showingDiagnostics = model.previewShowDiagnostics
            #endif
            // Resume the onboarding browser login in the visible Codex draft.
            if model.signingIn {
                model.providerSetup.beginAdding("codex", connected: model.connectedSources)
            }
        }
        .sheet(isPresented: $addingAPI) { GenericAPIForm(model: model) { model.providerSetup.addedAPI($0) } }
        .confirmationDialog(t("Remove this API, its key and local usage history?"), isPresented: Binding(
            get: { removingAPI != nil }, set: { if !$0 { removingAPI = nil } })) {
                if let config = removingAPI {
                    Button(t("Remove"), role: .destructive) {
                        Task { await model.removeAPI(config); model.providerSetup.expandedID = nil }
                    }
                }
            }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }.frame(minWidth: 700, idealWidth: 740, maxWidth: 1200, minHeight: 600).toggleStyle(SettingsSwitchStyle()).tint(QuotaClockColors.accent).accentColor(QuotaClockColors.accent)
    }
    private func heading(_ title: String) -> some View { Text(t(title)).font(.system(size: 20, weight: .semibold)) }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionTitleSpacing) {
            Text(t(title)).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: SettingsTokens.controlGap, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t(title)); Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.frame(minHeight: SettingsTokens.rowHeight)
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionGap) {
            HStack(spacing: 14) {
                logo(60)
                VStack(alignment: .leading, spacing: 5) { BrandWordmark(size: 26); Text(t("Your AI limits, at a glance.")).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                Button(action: reopenOnboarding) { HStack(spacing: 5) { Text(t("Open Guide")); Image(systemName: "arrow.right") } }
                    .buttonStyle(.plain).foregroundStyle(QuotaClockColors.accent)
            }
            section("Behavior") {
                Toggle(t("Show QuotaClock in Menu Bar"), isOn: menuVisible)
                Divider()
                Toggle(t("Launch at login"), isOn: Binding(get: {
                    loginStatus == .enabled || loginStatus == .requiresApproval
                }, set: { enabled in
                    guard !model.onboardingPreview else { return }
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch { loginError = error.localizedDescription }
                    loginStatus = SMAppService.mainApp.status
                }))
                if loginStatus == .requiresApproval {
                    Button(t("Approve in System Settings")) { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Divider()
                HStack {
                Text(t("Refresh Interval")); Spacer()
                Picker(t("Refresh Interval"), selection: Binding(get: { model.platform.refreshPreference }, set: {
                    var next = model.platform; next.refreshPreference = $0; model.savePlatform(next)
                })) {
                    ForEach(RefreshPreference.allCases, id: \.self) { Text(t($0.title)).tag($0) }
                }.labelsHidden().fixedSize().accessibilityLabel(t("Refresh Interval"))
                    .help(t("Refresh timing may be limited by the service and retry backoff."))
                }
                HStack { Spacer(); Button(t(model.refreshing ? "Refreshing…" : "Refresh All")) { Task { await model.refreshAll() } }.disabled(model.refreshing) }
            }
            section("Notifications") { ResetNotificationSettings(language: language, preview: model.onboardingPreview) }
            section("Appearance") {
                AppearanceSelection(model: model)
                LogoSelection(model: model)
            }
            section("Language") {
                LanguageSelectionRows(model: model, detailed: true)
            }
        }
    }
    private var providerRows: [String] {
        model.providerSetup.rows(connected: model.connectedSources)
    }
    private var providers: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(t("Connected Providers")).font(.headline)
                Spacer()
                Menu {
                    ForEach(ProviderCatalog.providers, id: \.id) { provider in
                        Button(provider.displayName) {
                            model.providerSetup.beginAdding(provider.id, connected: model.connectedSources)
                        }
                    }
                    Divider()
                    Button(t("Add API Provider")) { model.apiFeedback = nil; addingAPI = true }
                } label: { Label(t("Add Provider"), systemImage: "plus") }
                    .disabled(model.switchingAccountID != nil)
            }
            VStack(alignment: .leading, spacing: 12) {
                Picker(t("Hero provider"), selection: Binding(get: { model.selectedHeroProviderID }, set: { value in
                    var next = model.platform, configuration = model.displayConfiguration
                    configuration.heroProviderID = value; next.providerDisplay = configuration
                    model.savePlatform(next)
                })) {
                    if model.heroProviderIDs.isEmpty { Text(t("No providers configured")).tag("") }
                    ForEach(model.heroProviderIDs, id: \.self) { id in Text(model.providerBaseName(id)).tag(id) }
                }.disabled(model.heroProviderIDs.isEmpty)
                HStack {
                    Text("Auto Hero")
                    Spacer()
                    Toggle("Auto Hero", isOn: providerDisplay(\.autoHero)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Text(t("Auto Hero follows the signed-in account of your Hero provider. When off, displays follow your provider order."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if providerRows.isEmpty {
                Text(t("Add a provider to get started.")).foregroundStyle(.secondary)
            }
            ProviderReorderList(ids: providerRows,
                enabled: model.providerSetup.canReorder(connected: model.connectedSources,
                    busy: model.signingIn || model.switchingAccountID != nil),
                language: language, commit: model.reorderConnections) { id, handle in
                    DisclosureGroup(isExpanded: Binding(
                        get: { model.providerSetup.expandedID == id },
                        set: { model.providerSetup.expandedID = $0 ? id : nil })) {
                        providerDetail(id)
                    } label: {
                        HStack(spacing: 10) {
                            brand(id)
                            VStack(alignment: .leading, spacing: 4) {
                                ProviderConnectionTitle(name: model.providerBaseName(id), nickname: model.providerNickname(id))
                                if model.snapshot?.hero?.id == id {
                                    Text(t("Current Hero")).font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                                }
                            }
                            Spacer()
                            if model.providerSetup.pendingID == id && !model.connectedSources.contains(id) {
                                Text(t("Waiting")).font(.caption).foregroundStyle(.secondary)
                            } else {
                                ProviderQuotaSummary(provider: model.snapshot?.providers.first { $0.id == id },
                                                     enabled: model.enabled(id), language: language)
                            }
                        }
                    }.disclosureGroupStyle(ProviderDisclosureStyle(language: language, handle: handle,
                        cancel: model.providerSetup.pendingID == id && !model.connectedSources.contains(id) ? {
                            model.cancelAddingProvider(id)
                        } : nil))
            }
        }
    }
    private func providerDetail(_ providerID: String) -> some View {
        let definitions = model.productDefinitions.filter { $0.providerID == providerID && $0.connection != "account" && !(providerID.hasPrefix("codex") && model.platform.codexMultiAccount) }
        let provider = model.snapshot?.providers.first { $0.id == providerID }
        return VStack(alignment: .leading, spacing: 20) {
            if providerID == "codex" || providerID.hasPrefix("codex.account.") { CodexAccountsView(model: model, selectedAccountID: providerID == "codex" ? nil : providerID) }
            if !definitions.isEmpty { section("Products") {
                ForEach(definitions) { definition in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(definition.displayName, isOn: Binding(get: { model.platform.enabledProducts.contains(definition.id) }, set: { model.setProduct(definition.id, enabled: $0) }))
                            .disabled(!definition.supported)
                        if !definition.supported {
                            Text(t("Data source not verified")).font(.caption).foregroundStyle(.secondary)
                        } else if model.platform.enabledProducts.contains(definition.id) {
                            productConnection(definition, product: provider?.activeProducts.first { $0.id == definition.id })
                        }
                    }.padding(.vertical, 4)
                    if definition.id != definitions.last?.id { Divider() }
                }
            }
            }
            if model.enabled(providerID) && !(providerID.hasPrefix("codex") && model.platform.codexMultiAccount) {
                ProviderNicknameField(value: model.platform.preference(providerID).nickname ?? "", language: language, allowsEmpty: true, rename: {
                    model.saveNickname($0, for: providerID)
                })
                ProviderResetTimes(provider: provider, language: language)
            }
        }
    }
    private func productConnection(_ definition: ProductDescriptor, product: ProductQuota?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t(product?.health?.state.displayName ?? "Waiting")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(t("Refresh")) { model.refreshProduct(definition.id) }.controlSize(.small)
            }
            if let date = product?.health?.lastSuccess {
                Text("\(t("Last success")) \(date.formatted())").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let config = model.customAPIs.first(where: { $0.productID == definition.id }) {
                Text(t("Only requests made through QuotaClock are counted. Requests from other apps and account quotas are not available here."))
                    .font(.caption).foregroundStyle(.secondary)
                row("Protocol", "Responses")
                row("Model", config.model)
                Text(config.baseURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text(t("Validation sends a tiny fixed request and may incur a small API charge. Automatic refresh sends no model requests."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(t(model.validatingAPI ? "Validating…" : "Validate")) { Task { await model.validateAPI(config) } }
                    Button(t("Remove API"), role: .destructive) { removingAPI = config }
                }.disabled(model.validatingAPI).controlSize(.small)
                if let feedback = model.apiFeedback { Text(t(feedback)).font(.caption).textSelection(.enabled) }
            } else if definition.connection == "key" {
                SecureField(t("API Key"), text: Binding(get: { keys[definition.id] ?? "" }, set: { keys[definition.id] = $0 }))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(t("Save / Replace")) { model.saveKey(keys[definition.id] ?? "", product: definition); keys[definition.id] = nil }
                        .disabled(keys[definition.id, default: ""].isEmpty)
                    Button(t("Validate")) { model.refreshProduct(definition.id) }
                    Button(t("Remove")) { model.removeKey(definition) }
                }.controlSize(.small)
                Text(t("Stored in macOS Keychain for this product only.")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if definition.connection == "cli" {
                Text(t("Uses your official Bailian CLI login. Sign in with bl auth login --console in Terminal."))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                TextField(t("CLI profile"), text: Binding(get: { UserDefaults.standard.string(forKey: "profile.\(definition.id)") ?? "default" }, set: { model.setCLIProfile($0, productID: definition.id) }))
                    .textFieldStyle(.roundedBorder)
                Text(t("Refresh after changing the CLI profile.")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else { Text(t("Uses your local CLI session.")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func visibleServices(_ surface: DisplaySurface) -> some View {
        section("Visible AI Services") {
            ForEach(model.displaySources, id: \.self) { id in
                HStack {
                    Text(model.providerName(id))
                    Spacer()
                    Toggle(model.providerName(id), isOn: display(id, surface == .menuBar ? \.menuBarVisible : \.screenSaverVisible))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }.frame(minHeight: SettingsTokens.rowHeight)
            }
            if model.connectedSources.isEmpty { Text(t("Add a provider to get started.")).foregroundStyle(.secondary) }
        }
    }
    private var menuBar: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionGap) {
            MenuBarPartialPreview(model: model)
            Button(t("Open Preview")) { openWindow(id: "menu-preview") }
            section("Behavior") {
                Toggle(t("Show QuotaClock in Menu Bar"), isOn: menuVisible)
                if model.platform.showMenuBar {
                    Picker(t("Menu bar icon"), selection: Binding(get: { model.platform.effectiveMenuBarIconStyle(hasConfiguredProviders: !model.connectedSources.isEmpty) }, set: {
                        var next = model.platform; next.menuBarIconStyle = $0; model.savePlatform(next)
                    })) {
                        Text(t("Gauge icon")).tag(MenuBarIconStyle.clock)
                        Text(t("Provider logo")).tag(MenuBarIconStyle.provider)
                            .disabled(model.connectedSources.isEmpty)
                    }
                    if model.platform.effectiveMenuBarIconStyle(hasConfiguredProviders: !model.connectedSources.isEmpty) == .clock {
                        Picker(t("Icon color"), selection: Binding(get: { model.platform.menuBarGaugeColor }, set: {
                            var next = model.platform; next.menuBarGaugeColor = $0; model.savePlatform(next)
                        })) {
                            Text(t("Monochrome")).tag(MenuBarGaugeColor.monochrome)
                            Text(t("Color")).tag(MenuBarGaugeColor.color)
                        }
                    }
                    Picker(t("Dropdown position"), selection: Binding(get: { model.platform.menuBarAlignment }, set: {
                        var next = model.platform; next.menuBarAlignment = $0; model.savePlatform(next)
                    })) {
                        Text(t("Left")).tag(MenuBarAlignment.left)
                        Text(t("Center")).tag(MenuBarAlignment.center)
                        Text(t("Right")).tag(MenuBarAlignment.right)
                    }
                    Toggle(t("Show percentage or balance"), isOn: Binding(get: { model.platform.menuBarShowValue }, set: {
                        var next = model.platform; next.menuBarShowValue = $0; model.savePlatform(next)
                    }))
                    Text(t("Without a provider, the gauge appears. Add a provider to use its logo.")).font(.caption).foregroundStyle(.secondary)
                }
                Text(t("Hiding the menu bar does not stop refresh, widgets or the screen saver.")).font(.caption).foregroundStyle(.secondary)
                Divider()
                Picker(t("Maximum Providers"), selection: providerDisplay(\.menuLimit)) {
                    ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle(t("Use a large card for Hero"), isOn: Binding(get: { model.platform.menuBarHeroLarge }, set: {
                    var next = model.platform; next.menuBarHeroLarge = $0; model.savePlatform(next)
                }))
                Text(t("Provider order and Hero are managed in AI Services.")).font(.caption).foregroundStyle(.secondary)
            }
            visibleServices(.menuBar)
        }
    }
    private var saver: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionGap) {
            GeometryReader { area in
                let ratio = 16.0 / 9.0
                let canvas = CGSize(width: 1600, height: 1600 / ratio)
                AmbientDisplay(snapshot: MenuPreviewProjection.snapshot(model.snapshot?.displayProjection(), platform: model.platform), preferences: model.preferences, now: .now, page: 0, preview: false, accelerated: false, allowsMotion: false)
                    .frame(width: canvas.width, height: canvas.height)
                    .scaleEffect(area.size.width / canvas.width, anchor: .topLeading)
                    .frame(width: area.size.width, height: area.size.height, alignment: .topLeading)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Button(t("Open Preview")) { openWindow(id: "preview") }
            section("Display") {
                Picker(t("Maximum Providers"), selection: providerDisplay(\.saverLimit)) {
                    ForEach(2...3, id: \.self) { Text("\($0)").tag($0) }
                }
                Text(t("Provider order and Hero are managed in AI Services.")).font(.caption).foregroundStyle(.secondary)
                Text(t("Portrait shows the Hero and Secondary Card 1.")).font(.caption).foregroundStyle(.secondary)
            }
            section("Clock") {
                Toggle(t("Show Clock"), isOn: pref(\.showClock))
                Toggle(t("Show Date"), isOn: pref(\.showDate))
                Picker(t("Time Format"), selection: pref(\.timeFormat)) {
                    Text(t("Auto")).tag(AmbientTimeFormat.automatic)
                    Text(t("24-hour")).tag(AmbientTimeFormat.twentyFourHour)
                    Text(t("12-hour")).tag(AmbientTimeFormat.twelveHour)
                }
                if model.preferences.timeFormat == .twelveHour {
                    Toggle(t("Show AM/PM"), isOn: pref(\.showAMPM))
                }
                Toggle(t("Burn-in Protection"), isOn: pref(\.burnInProtection))
            }
            section("Behavior") { ScreenSaverSetupView(language: language, preview: model.onboardingPreview) }
            visibleServices(.screenSaver)
        }
    }
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionGap) {
            section("Widgets") {
                row("Widget extension registered", model.widgetRegistered.map { t($0 ? "Yes" : "No") } ?? t("Not checked"))
                row("Installed widget instances", model.widgetInstances.map(String.init) ?? "—")
                Text(t("Zero instances means no widgets have been added; it does not mean the extension is missing."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(t("Check Widgets"), action: model.inspectWidgets)
            }
            if let snapshot = model.snapshot {
                ForEach(snapshot.providers) { provider in
                    section(provider.displayName) {
                        ForEach(provider.activeProducts) { product in
                            row(product.displayName, t(product.health?.state.displayName ?? "Waiting"))
                            let reliability = product.meters.first?.reliability ?? model.productDefinitions.first(where: { $0.id == product.id })?.reliability ?? .unsupported
                            row("Source Reliability", t(reliability.displayName))
                            row("Last attempt", product.health?.lastAttempt?.formatted() ?? "—")
                            if product.id.hasPrefix("custom.") {
                                Text(t("Local aggregation status; validate separately to check API connectivity."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                DisclosureGroup(t("Advanced")) {
                    row("Revision", snapshot.revision.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    Text(t(model.status)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(t("Repair Display Export"), action: model.repairExport)
                        Button(t("Copy Sanitized Diagnostics"), action: model.copyDiagnostics)
                    }.controlSize(.small)
                }
            }
            Button(t("Refresh All")) { Task { await model.refreshAll() } }.disabled(model.refreshing)
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                logo(64)
                VStack(alignment: .leading, spacing: 5) {
                    BrandWordmark(size: 26)
                    Text(t("Your AI limits, at a glance.")).foregroundStyle(.secondary)
                }
            }
            section("Version") {
                row("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                row("Build", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            section("Software Updates") { AppUpdateSettings(language: language) }
            Button { showingDiagnostics = true } label: {
                Label(t("Diagnostics"), systemImage: "waveform.path.ecg")
            }
            DisclosureGroup(t("Licenses")) {
                Link("Sparkle · MIT", destination: URL(string: "https://sparkle-project.org")!)
                Text("Lobe Icons · MIT · © LobeHub")
                if let url = Bundle.main.url(forResource: "LobeIcons-LICENSE", withExtension: nil),
                   let license = try? String(contentsOf: url, encoding: .utf8) {
                    Text(license).font(.caption).textSelection(.enabled)
                }
                Text(t("Provider names and logos belong to their respective owners.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

}


private struct ProviderDisclosureStyle: DisclosureGroupStyle {
    let language: AppLanguage
    let handle: ProviderDragHandle
    let cancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                handle
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { configuration.isExpanded.toggle() }
                } label: {
                    configuration.label.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityValue(AppText.value(configuration.isExpanded ? "Expanded" : "Collapsed", language))
                if let cancel {
                    Button(AppText.value("Cancel", language), action: cancel).controlSize(.small)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { configuration.isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 16, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(AppText.value(configuration.isExpanded ? "Collapse" : "Expand", language))
            }.padding(10)
            if configuration.isExpanded {
                Divider().padding(.horizontal, 12)
                configuration.content.padding(12)
            }
        }.background(configuration.isExpanded ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.035),
                     in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Extend the system sidebar material behind the traffic lights and toolbar.
private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

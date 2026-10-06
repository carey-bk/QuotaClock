import SwiftUI
import QuotaCore
import CoreText

private enum WelcomeStyle {
    // Load the bundled face directly, independent of fonts installed on the Mac.
    // Both Chinese greetings use the same two glyphs: 你好.
    static let chineseGreeting: Font = {
        guard let url = Bundle.main.url(forResource: "SourceHanSansCN-Regular", withExtension: "otf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return .system(size: 62, weight: .regular)
        }
        return Font(CTFontCreateWithFontDescriptor(descriptor, 62, nil))
    }()
    static let gold = QuotaClockColors.accent
    static let silver = Color(red: 0.69, green: 0.73, blue: 0.78)
    static let buttonInk = Color(red: 0.17, green: 0.15, blue: 0.11)
}

struct OnboardingView: View {
    @ObservedObject var model: SnapshotController
    @ObservedObject var flow: OnboardingController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var nickname = ""
    @State private var copiedSignInLink = false
    @State private var addingConnection = false
    @State private var selectedSource: String?
    @State private var laterHovered = false
    @AccessibilityFocusState private var titleFocused: Bool
    private var language: AppLanguage { model.preferences.language }
    private var step: OnboardingStep { flow.progress.step }
    private var reduced: Bool { reduceMotion || (model.onboardingPreview && model.previewReduceMotion) }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private var sources: [String] { model.connectedSources }
    private var currentSource: String? {
        if let selectedSource, sources.contains(selectedSource) { return selectedSource }
        return sources.first
    }
    private var provider: ProviderQuota? {
        model.snapshot?.providers.first { $0.id == currentSource }
    }
    private var readyCount: Int {
        model.snapshot?.providers.filter { model.enabled($0.id) && OnboardingReadiness.usable($0) }.count ?? 0
    }
    private var titles: [String] { ["Your AI limits, at a glance.", "Appearance", "Connect your first account.", "Keep your limits in sight.", "Your workspace is ready."] }
    private var descriptions: [String] { [
        "See account limits and balances in your menu bar, widgets and screen saver.",
        "Choose light, dark, or follow your Mac automatically.",
        "Sign in to save an independent Codex account, or link the current account on this Mac.",
        "Choose a few everyday preferences. Changes are saved immediately and can be changed in Settings.",
        "Review what is available now. You can enter QuotaClock even if an account still needs attention."
    ] }
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 640
            VStack(spacing: 0) {
                brand.padding(.bottom, compact ? 20 : 30)
                HStack(alignment: .center, spacing: 28) {
                    introduction.frame(width: 300, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .topLeading).padding(.top, 42)
                    page.frame(maxWidth: 408).frame(maxWidth: .infinity)
                }
                .id(step)
                .transition(reduced ? .opacity : .asymmetric(
                    insertion: .offset(x: flow.movingForward ? 30 : -30).combined(with: .opacity),
                    removal: .offset(x: flow.movingForward ? -20 : 20).combined(with: .opacity)))
                .allowsHitTesting(!flow.transitioning)
                .accessibilityHidden(flow.transitioning)
                .frame(maxHeight: .infinity)
                footer.padding(.top, compact ? 16 : 24)
            }
            .padding(.horizontal, 32)
            .padding(.top, 46)
            .padding(.bottom, 26)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(background)
        }
        .frame(minWidth: 820, idealWidth: 820, minHeight: 568, idealHeight: 568)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .tint(WelcomeStyle.gold)
        .toggleStyle(SettingsSwitchStyle())
        .onChange(of: model.signInPrompt?.url) { _, _ in copiedSignInLink = false }
        .onChange(of: step) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduced ? 140 : 420))
                titleFocused = true
            }
        }
        .onChange(of: model.providerSetup.completedSourceID) { _, source in
            if let source { selectedSource = source; addingConnection = false }
        }
    }
    private var background: some View {
        GeometryReader { g in
            let positions: [UnitPoint] = [.init(x: 0.95, y: 0.8), .init(x: 0.75, y: 0.7), .init(x: 0.8, y: 0.18), .init(x: 0.2, y: 0.8), .init(x: 0.65, y: 0.55)]
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [WelcomeStyle.gold.opacity(scheme == .dark ? 0.14 : 0.17), .clear],
                    center: positions[step.position], startRadius: 0, endRadius: g.size.width * 0.78)
                RadialGradient(colors: [WelcomeStyle.silver.opacity(scheme == .dark ? 0.13 : 0.22), .clear],
                    center: .topLeading, startRadius: 0, endRadius: g.size.width * 0.8)
            }.animation(reduced ? nil : .easeInOut(duration: 1.2), value: step)
        }.ignoresSafeArea()
    }
    private var brand: some View {
        HStack(spacing: 10) {
            AppLogoView(style: model.platform.appLogo, size: 30)
                .accessibilityHidden(true)
            Text("QuotaClock").font(.system(size: 19, weight: .semibold))
            Spacer()
            if model.signingIn {
                ProgressView().controlSize(.small)
                Text(t("Connecting…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.frame(height: 34)
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t(titles[step.position])).font(.system(size: 32, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
            Text(t(descriptions[step.position])).font(.system(size: 14)).lineSpacing(4)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if step == .welcome {
                LanguageSelectionRows(model: model).padding(.top, 8)
            } else if step == .appearance {
                AppearanceSelection(model: model, compact: true).padding(.top, 8)
                LogoSelection(model: model)
            } else if step == .connection {
                Label(t("Your current Codex login stays unchanged."), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text(t("Signing in saves credentials for ongoing monitoring. Linking only reads the current session; monitoring stops if you sign out or switch accounts."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if step == .display {
                Label(t("Your existing choices are preserved."), systemImage: "checkmark.shield")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Label(t("Setup can continue in Settings."), systemImage: "slider.horizontal.3")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var page: some View {
        switch step {
        case .welcome: welcome
        case .appearance: appearancePreview
        case .connection: connection
        case .display: display
        case .ready: summary
        }
    }
    private var appearancePreview: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 5) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { color in
                            Circle().fill(color.opacity(0.75)).frame(width: 7, height: 7)
                        }
                    }
                    AppLogoView(style: model.platform.appLogo, size: 36)
                    ForEach(["gearshape", "square.3.layers.3d", "menubar.rectangle", "display"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(18).frame(width: 82).background(Color.primary.opacity(0.05))
                VStack(alignment: .leading, spacing: 18) {
                    Text("QuotaClock").font(.system(size: 21, weight: .semibold))
                    ForEach(["ProviderOpenAI", "ProviderClaude", "ProviderDeepSeek"], id: \.self) { asset in
                        HStack(spacing: 12) {
                            Image(asset).renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.primary)
                            VStack(alignment: .leading, spacing: 8) {
                                Capsule().fill(Color.primary.opacity(0.5)).frame(width: 70, height: 6)
                                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 5)
                            }
                        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(20).frame(maxWidth: .infinity)
            }.frame(height: 285)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.09)))
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
                .accessibilityHidden(true)
            Text(t("You can change this anytime in Settings."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private var welcome: some View {
        VStack(spacing: 18) {
            WelcomeGreeting(language: language, reducedMotion: reduced)
            AppLogoView(style: model.platform.appLogo, size: 128)
                .frame(width: 128, height: 128).accessibilityLabel("QuotaClock")
            OnboardingSurfacesView(language: language)
            Text(t("One view of your accounts. No invented quota."))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 26)
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !sources.isEmpty && !addingConnection {
                Picker(t("Saved connection"), selection: Binding(get: { currentSource ?? "" }, set: { selectedSource = $0 })) {
                    ForEach(sources, id: \.self) { Text(model.providerName($0)).tag($0) }
                }
                if let provider {
                    ProviderCard(provider: provider, density: .medium, saverPanel: true, language: model.preferences.effectiveWidgetLanguage)
                        .frame(width: 360, height: 170)
                } else {
                    statusLine("Waiting for quota data", symbol: "clock")
                }
                Text(t(provider.map(OnboardingReadiness.usable) == true ? "Quota data is available." : "Connection saved. Quota data is not verified yet."))
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        refreshConnectionButton
                        Spacer(minLength: 12)
                        linkAnotherAccountButton
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        refreshConnectionButton
                        linkAnotherAccountButton
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image("ProviderOpenAI").resizable().scaledToFit().frame(width: 30, height: 30)
                    Text("Codex").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text(t(model.signingIn ? "Connecting…" : model.accountFeedback == nil ? "Not started" : "Connection needs attention"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(t("Sign in through your browser to add an independent account."))
                    .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                TextField(t("Account nickname"), text: $nickname).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(t("Account nickname"))
                Text(t("Use 1–12 English letters for the signature."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if model.signingIn {
                    Text(t(model.signInPrompt == nil ? "Preparing sign-in…" : "Finish signing in in your browser, then return here. No device code is needed."))
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let prompt = model.signInPrompt {
                            Link(t("Open Sign-in Page"), destination: prompt.url)
                            Button(t(copiedSignInLink ? "Link Copied" : "Copy Sign-in Link")) {
                                NSPasteboard.general.clearContents()
                                copiedSignInLink = NSPasteboard.general.setString(prompt.url.absoluteString, forType: .string)
                            }
                        }
                        Button(t("Cancel")) {
                            if model.onboardingPreview { model.signingIn = false; model.signInPrompt = nil }
                            else { model.cancelCodexSignIn() }
                        }
                    }
                } else {
                    Button(t("Sign in to Codex")) {
                        if model.onboardingPreview { model.signingIn = true; model.accountFeedback = nil }
                        else { model.signInCodex(signature: nickname) }
                    }.buttonStyle(.borderedProminent)
                        .disabled(!ProviderAccount.validSignature(nickname) || model.switchingAccountID != nil)
                    Button(t("Link current Codex account")) {
                        if model.onboardingPreview { model.accountFeedback = "No Codex login found. Open Codex, sign in, then retry." }
                        else { model.linkCodex(signature: nickname) }
                    }.buttonStyle(.link)
                        .disabled(!ProviderAccount.validSignature(nickname) || model.switchingAccountID != nil)
                }
                if let feedback = model.accountFeedback {
                    Label(t(feedback), systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                if !sources.isEmpty {
                    Button(t("Use saved connections")) { addingConnection = false }.buttonStyle(.link)
                }
            }
        }.padding(24).background(panel)
    }
    private var refreshConnectionButton: some View {
        Button(t(model.refreshing ? "Refreshing…" : "Validate / Refresh")) {
            if !model.onboardingPreview { Task { await model.refreshAll() } }
        }.disabled(model.refreshing).fixedSize()
    }
    private var linkAnotherAccountButton: some View {
        Button(t("Add another Codex account")) { addingConnection = true; model.accountFeedback = nil }
            .buttonStyle(.link).fixedSize()
    }
    private var display: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(t("Show QuotaClock in Menu Bar"), isOn: Binding(get: { model.platform.showMenuBar }, set: {
                var next = model.platform; next.showMenuBar = $0; model.savePlatform(next)
            }))
            Picker(t("Menu bar cards"), selection: displayPreference(\.menuLimit)) {
                ForEach(1...3, id: \.self) { Text(String($0)).tag($0) }
            }
            Divider()
            Toggle("Auto Hero", isOn: displayPreference(\.autoHero))
            Text(t("Auto Hero follows the signed-in account of your Hero provider. When off, displays follow your provider order."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Picker(t("Screen saver cards"), selection: displayPreference(\.saverLimit)) {
                ForEach(2...3, id: \.self) { Text(String($0)).tag($0) }
            }
            ScreenSaverSetupView(language: language, preview: model.onboardingPreview, compact: true)
        }.font(.system(size: 14)).padding(24).background(panel)
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusLine("Saved connections", value: String(sources.count), symbol: "person.crop.circle")
            statusLine("Accounts with quota data", value: String(readyCount), symbol: "chart.bar")
            statusLine("Menu Bar", value: t(model.platform.showMenuBar ? "Enabled" : "Disabled"), symbol: "menubar.rectangle")
            Divider()
            Text(t(readyCount > 0 ? "Your connected accounts are available in Providers. Refresh there whenever you need an update." : "No verified quota yet. Open Providers to link an account or retry a connection."))
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Text(t("Add a QuotaClock widget from your desktop. Choose QuotaClock in macOS Screen Saver settings."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.error != nil {
                Label(t("Some settings could not be saved. Open About → Diagnostics and try again."), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(24).background(panel)
    }
    private func statusLine(_ title: String, value: String? = nil, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(WelcomeStyle.gold).accessibilityHidden(true)
            Text(t(title)); Spacer(minLength: 12)
            if let value { Text(value).fontWeight(.medium).monospacedDigit() }
        }.font(.system(size: 14)).frame(minHeight: 28)
    }
    private var panel: some View {
        RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(scheme == .dark ? 0.65 : 0.73))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.07)))
    }
    private var footer: some View {
        HStack(alignment: .center, spacing: 18) {
            Button { flow.move(-1, reducedMotion: reduced) } label: {
                Image(systemName: "chevron.left").frame(width: 28, height: 28)
            }.buttonStyle(.plain).accessibilityLabel(t("Back"))
                .disabled(step == .welcome || flow.transitioning)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases, id: \.self) { item in
                        Capsule().fill(item == step ? WelcomeStyle.gold : item.position < step.position ? WelcomeStyle.gold.opacity(0.4) : Color.primary.opacity(0.12))
                            .frame(width: item == step ? 46 : 26, height: 7)
                    }
                }.animation(reduced ? nil : .spring(response: 0.48, dampingFraction: 0.86), value: step)
                    .accessibilityHidden(true)
                Text(String(format: t("Step %d of %d"), step.position + 1, OnboardingStep.allCases.count))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 18)
            Button(t("Set up later")) { flow.deferSetup() }
                .buttonStyle(.plain).foregroundStyle(laterHovered ? WelcomeStyle.gold : .secondary)
                .underline(laterHovered).onHover { laterHovered = $0 }
                .help(t("Leave the guide now. Resume it from General settings."))
                .disabled(flow.transitioning)
            Button {
                if step == .ready { flow.finish() }
                else { flow.move(1, reducedMotion: reduced) }
            } label: {
                Text(t(step == .ready ? "Open QuotaClock" : "Continue"))
                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).frame(height: 42)
                    .foregroundStyle(WelcomeStyle.buttonInk)
                    .background(LinearGradient(colors: [Color(red: 0.89, green: 0.83, blue: 0.68), Color(red: 0.80, green: 0.71, blue: 0.53)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(flow.transitioning)
        }.frame(height: 48)
    }
    private func preference<T>(_ path: WritableKeyPath<AmbientPreferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: path] }, set: {
            var next = model.preferences; next[keyPath: path] = $0; model.savePreferences(next)
        })
    }
    private func displayPreference<T>(_ path: WritableKeyPath<ProviderDisplayConfiguration, T>) -> Binding<T> {
        Binding(get: { model.displayConfiguration[keyPath: path] }, set: {
            var next = model.platform, configuration = model.displayConfiguration
            configuration[keyPath: path] = $0; next.providerDisplay = configuration; model.savePlatform(next)
        })
    }
}

private struct WelcomeGreeting: View {
    let language: AppLanguage
    let reducedMotion: Bool
    @State private var displayedLanguage: AppLanguage?

    // Separate the two Chinese variants so identical greetings never appear consecutively.
    private let languages: [AppLanguage] = [.english, .chinese, .japanese, .traditionalChinese, .korean, .french]
    private var current: AppLanguage { displayedLanguage ?? language }
    private var font: Font {
        switch current {
        case .chinese, .traditionalChinese: WelcomeStyle.chineseGreeting
        default: .system(size: 62, weight: .light, design: .serif)
        }
    }

    var body: some View {
        ZStack {
            Text(AppText.value("Hello", current))
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .id(current)
                .transition(.opacity)
        }
        // Keep the logo and captions stationary as glyph metrics change.
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .animation(reducedMotion ? nil : .easeInOut(duration: 0.4), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppText.value("Hello", language))
        .task(id: language) {
            displayedLanguage = language
            var index = languages.firstIndex(of: language) ?? 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard !Task.isCancelled else { return }
                index = (index + 1) % languages.count
                displayedLanguage = languages[index]
            }
        }
    }
}

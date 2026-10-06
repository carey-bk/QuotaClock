import SwiftUI
import QuotaCore

/// Presentation only; preview fixtures never construct a publisher or fetch provider data.
struct MenuCardsView: View {
    @Binding var choosingAccount: Bool
    let snapshot: QuotaSnapshot?
    let language: AppLanguage
    let refreshing: Bool
    var hasConfiguredProviders: Bool = true
    var accountOptions: [CodexAccountSwitchOption] = []
    var switchingAccountID: UUID?
    var switchingStatus: String?
    var switchFeedback: String?
    var accountActionsDisabled = false
    var switchAccount: (UUID) -> Void = { _ in }
    var refresh: () -> Void
    var showSettings: () -> Void
    var quit: () -> Void
    var cardViewportHeight: CGFloat? = nil
    var presentationID = 0
    var forceReducedMotion = false
    var largeHero = false
    var previewOnly = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0
    private var reduced: Bool { reduceMotion || forceReducedMotion }
    private var hasFeedback: Bool { switchingStatus != nil || switchFeedback != nil }
    private var motion: Animation? { reduced ? nil : .timingCurve(0.22, 0.8, 0.25, 1, duration: 0.32) }
    private var shown: QuotaSnapshot? { snapshot?.forSurface(.menuBar) }
    private var cards: [ProviderQuota] {
        Array((shown?.providers ?? []).prefix(8))
    }
    private var largeHeroID: String? { largeHero ? snapshot?.hero?.id : nil }
    private var contentHeight: Double {
        MenuCardLayout.contentHeight(cards: cards.count, largeHero: cards.contains { $0.id == largeHeroID })
    }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private var emptyMessage: String {
        if !hasConfiguredProviders { return "No providers configured" }
        return snapshot?.providers.isEmpty != false ? "Waiting for quota data" : "No active providers."
    }
    var body: some View {
        Group {
        if cards.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(t(emptyMessage))
                    .font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
                Button(t(hasConfiguredProviders ? "Settings" : "Configure a provider"), action: showSettings)
                    .buttonStyle(.borderedProminent)
                if !accountOptions.isEmpty { accountMenu }
                if let message = switchingStatus ?? switchFeedback {
                    Text(t(message)).font(.caption).multilineTextAlignment(.center)
                }
                Button(t("Quit"), action: quit).buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(switchingAccountID != nil)
            }
            .padding(24).frame(width: 372).frame(maxHeight: .infinity)
            .foregroundStyle(.primary)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        } else {
        GeometryReader { area in
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, provider in
                        let large = provider.id == largeHeroID
                        ProviderCard(provider: provider, density: large ? .full : .medium, language: language)
                            .frame(width: MenuCardLayout.width, height: MenuCardLayout.height(large: large))
                            .opacity(revealed > index ? 1 : 0)
                            .offset(y: reduced || revealed > index ? 0 : -9)
                    }
                }.padding(2)
                    .padding(.bottom, contentHeight > (cardViewportHeight ?? (area.size.height - 54 - (hasFeedback ? 48 : 0))) ? 24 : 0)
            }.frame(height: cardViewportHeight ?? max(70, min(contentHeight, area.size.height - 54 - (hasFeedback ? 48 : 0))))
                .mask(alignment: .bottom) {
                    if contentHeight > (cardViewportHeight ?? (area.size.height - 54 - (hasFeedback ? 48 : 0))) {
                        VStack(spacing: 0) {
                            Rectangle()
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        }
                    } else { Rectangle() }
                }
            if let message = switchingStatus ?? switchFeedback {
                HStack(spacing: 8) {
                    if switchingStatus != nil { ProgressView().controlSize(.small) }
                    Text(t(message)).font(.system(size: 11)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 10).frame(height: 36)
                    .background(GlassCardBackground(radius: 10))
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .offset(y: reduced ? 0 : -6)))
            }
            HStack(spacing: 8) {
                accountMenu
                if let date = snapshot?.generatedAt {
                    Group {
                        if refreshing { Text(t("Refreshing…")) }
                        else { Text("\(t("Updated")) \(date, style: .relative)") }
                    }.font(.system(size: 11))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(GlassCardBackground(radius: 12))
                }
                if refreshing {
                    ProgressView().controlSize(.small).tint(.white)
                        .frame(width: 38, height: 34)
                        .background(GlassCardBackground(radius: 12))
                        .accessibilityLabel(t("Refreshing…"))
                } else {
                    glassButton("Refresh", "arrow.clockwise", action: refresh)
                        .disabled(switchingAccountID != nil)
                }
                glassButton("Settings", "gearshape", action: showSettings)
                glassButton("Quit", "power") { quit() }.disabled(switchingAccountID != nil)
            }.foregroundStyle(.white).disabled(previewOnly)
                .opacity(revealed > cards.count ? 1 : 0)
                .offset(y: reduced || revealed > cards.count ? 0 : -6)
        }.padding(4).frame(width: 372).frame(maxHeight: .infinity, alignment: .top)
            .animation(motion, value: hasFeedback)
            .environment(\.colorScheme, .dark)
        }
        }
        }
        .task(id: presentationID) {
            revealed = reduced ? cards.count + 1 : 0
            guard !reduced else { return }
            // Every opening starts a fresh, cancellable top-to-bottom reveal.
            for level in 1...(cards.count + 1) {
                do { try await Task.sleep(for: .milliseconds(level == 1 ? 20 : 65)) } catch { return }
                withAnimation(motion) { revealed = level }
            }
        }
        .onChange(of: cards.count) { _, count in revealed = count + 1 }
        .onDisappear { choosingAccount = false }
    }

    private var accountMenu: some View {
        glassButton("Switch Codex Account", "arrow.left.arrow.right") {
            choosingAccount.toggle()
        }
        .disabled(accountOptions.isEmpty || accountActionsDisabled || switchingAccountID != nil)
    }
    private func glassButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 38, height: 34)
                .background(GlassCardBackground(radius: 12))
        }.buttonStyle(.plain).help(t(title)).accessibilityLabel(t(title))
    }
}

/// A separate small glass panel, so opening accounts never steals height from quota cards.
struct CodexAccountChooserView: View {
    let language: AppLanguage
    let options: [CodexAccountSwitchOption]
    var disabled = false
    var choose: (UUID) -> Void
    var dismiss: () -> Void
    static let width: CGFloat = 252
    static func height(accountCount: Int) -> CGFloat { min(292, CGFloat(accountCount) * 38 + 110) }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Switch Codex Account")).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).accessibilityLabel(t("Cancel"))
            }
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(options) { option in
                        Button { choose(option.id) } label: {
                            HStack(spacing: 8) {
                                Text("Codex \(option.name)").lineLimit(1)
                                Spacer(minLength: 4)
                                if option.isCurrent { Image(systemName: "checkmark") }
                                else if !option.canSwitch { Image(systemName: "person.crop.circle.badge.exclamationmark") }
                            }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 33)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(option.isCurrent ? 0.045 : 0.09), in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!option.canSwitch || disabled)
                            .help(t(option.isCurrent ? "Current account" : option.canSwitch ? "Switch Codex Account" : "Sign In Required"))
                    }
                }
            }.frame(maxHeight: .infinity)
            Text(t("Automatically restarts Codex. Running tasks will be interrupted."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white)
            .background(GlassCardBackground(radius: 18, readabilityShade: 0.1))
            .environment(\.colorScheme, .dark)
    }
}

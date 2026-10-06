import SwiftUI
import QuotaCore

/// The app preview and the legacy saver host share this placement of ProviderCard compositions.
struct AmbientDisplay: View {
    let snapshot: QuotaSnapshot?
    let preferences: AmbientPreferences
    let now: Date
    let page: Int
    let preview: Bool
    let accelerated: Bool
    var allowsMotion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: QuotaSnapshot? { snapshot?.forSurface(.screenSaver) }
    private var hero: ProviderQuota? {
        if snapshot?.platformPreferences?.providerDisplay != nil { return shown?.providers.first }
        return shown?.hero ?? shown?.providers.first { $0.displayPreference?.heroEligible ?? true }
    }
    private var locale: Locale { Locale(identifier: preferences.effectiveSaverLanguage.localeIdentifier) }

    var body: some View {
        GeometryReader { outer in
            let isPortrait = outer.size.height > outer.size.width * 1.15
            let selectedOthers = snapshot?.saverSecondaryProviders(portrait: isPortrait) ?? []
            let layout = AmbientLayoutEngine.layout(width: outer.size.width, height: outer.size.height,
                providerCount: 1 + selectedOthers.count, preview: preview)
            let drift = AmbientLayoutEngine.burnInOffset(
                at: accelerated ? now.addingTimeInterval(now.timeIntervalSince1970 * 30) : now,
                enabled: preferences.burnInProtection && !preview && allowsMotion)
            ZStack(alignment: .topLeading) {
                AmbientBackdrop()
                Group {
                    if !layout.preview && (preferences.showClock || preferences.showDate) {
                        clockLine(width: layout.clock.width)
                            .frame(width: layout.clock.width, height: layout.clock.height,
                                   alignment: .topTrailing)
                            .offset(x: layout.clock.x, y: layout.clock.y)
                    }
                    scaledCard(provider: hero, density: layout.preview ? .compact : .ambientHero,
                               base: layout.preview ? CGSize(width: 170, height: 170) : CGSize(width: 360, height: 360))
                        .frame(width: layout.hero.width, height: layout.hero.height)
                        .offset(x: layout.hero.x, y: layout.hero.y)
                        .id(hero?.id ?? "empty")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                    if let rail = layout.rail {
                        railCards(layout: layout, cards: selectedOthers)
                            .frame(width: rail.width, height: rail.height, alignment: .bottom)
                            .offset(x: rail.x, y: rail.y)
                    }
                }
                .offset(x: drift.x, y: drift.y)
            }
            .frame(width: outer.size.width, height: outer.size.height)
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: hero?.id)
        }
        .environment(\.colorScheme, .dark)
    }

    private func clockLine(width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: width * 0.02) {
            if preferences.showClock {
                Text(AmbientTimeText.time(now, format: preferences.timeFormat, showAMPM: preferences.showAMPM, locale: locale))
                    .font(.system(size: width * 0.112, weight: .regular, design: .serif))
                    .monospacedDigit()
            }
            if preferences.showDate {
                Text(now.formatted(.dateTime.month(.abbreviated).day().weekday(.wide).locale(locale)))
                    .font(.system(size: width * 0.04, weight: .regular, design: .serif))
                    .foregroundStyle(ProviderCardTokens.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .trailing)
            .foregroundStyle(ProviderCardTokens.ink).lineLimit(1).minimumScaleFactor(0.65)
    }

    private func scaledCard(provider: ProviderQuota?, density: ProviderCardDensity, base: CGSize) -> some View {
        GeometryReader { area in
            let scale = max(0.45, min(area.size.width / base.width, area.size.height / base.height))
            // Typography and spacing are laid out at the destination size.
            // Scaling a small rendered card blurs text in the saver host.
            ProviderCard(provider: provider, density: density,
                saverPanel: true,
                language: preferences.effectiveSaverLanguage, layoutScale: scale)
                .frame(width: area.size.width, height: area.size.height)
        }
    }

    private func railCards(layout: AmbientLayout, cards: [ProviderQuota]) -> some View {
        let slots = max(1, layout.itemsPerPage)
        let visible = Array(cards.prefix(slots))
        let square = layout.railDensity == .square
        let desiredHeight = square ? layout.rail!.width : layout.rail!.width / 360 * 170
        let rowHeight = min(desiredHeight, (layout.rail!.height - CGFloat(max(0, visible.count - 1)) * 12
                               ) / CGFloat(max(1, visible.count)))
        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            ForEach(visible) { provider in
                scaledCard(provider: provider, density: square ? .full : .ambientRail, base: CGSize(width: 360, height: square ? 360 : 170))
                    .frame(height: max(70, rowHeight))
            }

        }
        .foregroundStyle(ProviderCardTokens.ink)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: page)
    }
}

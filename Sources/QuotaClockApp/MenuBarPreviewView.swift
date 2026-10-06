import SwiftUI
import QuotaCore

/// A pure projection of the existing presentation snapshot. No controller, timer,
/// publisher or adapter is created by either preview surface.
struct MenuBarPreviewView: View {
    @ObservedObject var model: SnapshotController
    var body: some View {
        MenuCardsView(choosingAccount: .constant(false), snapshot: MenuPreviewProjection.snapshot(model.snapshot, platform: model.platform),
            language: model.preferences.effectiveMenuLanguage, refreshing: false,
            hasConfiguredProviders: !model.connectedSources.isEmpty,
            refresh: {}, showSettings: {}, quit: {}, forceReducedMotion: true, largeHero: model.platform.menuBarHeroLarge, previewOnly: true)
            .allowsHitTesting(false)
    }
}
/// A small desktop stage anchors the status item while the menu moves around it.
/// Use the same alignment calculation and status renderer as the live panel.
private struct MenuBarPreviewStage: View {
    @ObservedObject var model: SnapshotController
    var full = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let scale = full ? 1.0 : min(0.8, (geometry.size.width / 2 - 16) / 372)
            let status = MenuBarStatusLabel(snapshot: model.connectedSources.isEmpty ? nil : model.snapshot,
                language: model.preferences.effectiveMenuLanguage,
                iconStyle: model.platform.effectiveMenuBarIconStyle(hasConfiguredProviders: !model.connectedSources.isEmpty),
                showValue: model.platform.menuBarShowValue, gaugeColor: model.platform.menuBarGaugeColor,
                appearance: NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)).statusImage
            let anchorWidth = status.size.width + 14
            let anchorX = geometry.size.width / 2
            let x = model.platform.menuBarAlignment.origin(anchorMin: anchorX - anchorWidth / 2,
                anchorMax: anchorX + anchorWidth / 2, width: 372 * scale,
                screenMin: 0, screenMax: geometry.size.width)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [QuotaClockColors.accentSoft, Color.primary.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if full {
                    MenuCardsView(choosingAccount: .constant(false), snapshot: MenuPreviewProjection.snapshot(model.snapshot, platform: model.platform),
                        language: model.preferences.effectiveMenuLanguage, refreshing: false,
                        hasConfiguredProviders: !model.connectedSources.isEmpty, refresh: {}, showSettings: {}, quit: {},
                        forceReducedMotion: true, largeHero: model.platform.menuBarHeroLarge, previewOnly: true)
                        .frame(width: 372, height: max(200, geometry.size.height - 44))
                        .offset(x: x, y: 38)
                } else {
                    MenuBarPreviewView(model: model).frame(width: 372, height: 1000)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: 372 * scale, height: 1000 * scale, alignment: .topLeading)
                        .offset(x: x, y: 38)
                }
                Rectangle().fill(.ultraThinMaterial).frame(height: 30)
                    .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                    Text("QuotaClock").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }.font(.system(size: 10)).padding(.horizontal, 12).frame(height: 30)
                Image(nsImage: status).foregroundStyle(.primary)
                    .padding(.horizontal, 7).frame(height: 26)
                    .background(.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                    .offset(x: anchorX - anchorWidth / 2, y: 2)
            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.platform.menuBarAlignment)
                .clipped()
        }.accessibilityLabel(AppText.value("Menu Bar Preview", model.preferences.language))
    }
}
struct MenuBarPartialPreview: View {
    @ObservedObject var model: SnapshotController
    var body: some View {
        MenuBarPreviewStage(model: model).frame(height: 300)
            .mask { VStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 30) } }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsTokens.previewRadius))
            .clipShape(RoundedRectangle(cornerRadius: SettingsTokens.previewRadius))
    }
}
struct FullMenuBarPreview: View {
    @ObservedObject var model: SnapshotController
    var body: some View {
        MenuBarPreviewStage(model: model, full: true)
            .frame(minWidth: 780, idealWidth: 780, maxWidth: 900, minHeight: 400, idealHeight: 650, maxHeight: 1000)
            .navigationTitle(AppText.value("Menu Bar Preview", model.preferences.language))
    }
}

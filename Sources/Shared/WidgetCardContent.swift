import SwiftUI
import WidgetKit
import QuotaCore

/// WidgetKit archives this background. Live glass/material belongs to the system widget host,
/// not to the full-color card; an opaque base keeps text legible in both macOS appearances.
struct WidgetCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.19, blue: 0.20), Color(red: 0.10, green: 0.11, blue: 0.12)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.035), .white.opacity(0.10)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
            }
    }
}

/// The same foreground is used by the extension and by the offline appearance checks.
struct WidgetCardContent: View {
    let provider: ProviderQuota?
    let family: WidgetFamily
    let language: AppLanguage
    let renderingMode: WidgetRenderingMode
    var body: some View {
        GeometryReader { area in
            let base = family == .systemSmall ? CGSize(width: 170, height: 170) :
                family == .systemMedium ? CGSize(width: 360, height: 170) : CGSize(width: 360, height: 360)
            let scale = max(0.45, min(area.size.width / base.width, area.size.height / base.height))
            ProviderCard(provider: provider,
                density: family == .systemSmall ? .compact : family == .systemMedium ? .medium : .full,
                drawsPanel: false, language: language, layoutScale: scale, usesSystemTint: renderingMode != .fullColor)
                .frame(width: area.size.width, height: area.size.height)
        }
    }
}

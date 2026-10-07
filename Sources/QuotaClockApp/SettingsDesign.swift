import SwiftUI
import QuotaCore

enum QuotaClockColors {
    // The champagne gold used by the original welcome guide.
    static let accent = Color(red: 0.70, green: 0.57, blue: 0.34)
    static let accentSoft = accent.opacity(0.10)
    static let accentHover = accent.opacity(0.16)
    static let accentSelectedBackground = accent.opacity(0.12)
    static let accentBorder = accent.opacity(0.85)
}
enum SettingsTokens {
    static let pageHorizontalPadding: CGFloat = 24
    static let pageTopPadding: CGFloat = 22
    static let contentWidth: CGFloat = 820
    static let sectionGap: CGFloat = 26
    static let sectionTitleSpacing: CGFloat = 12
    static let rowHeight: CGFloat = 30
    static let rowVerticalPadding: CGFloat = 4
    static let controlGap: CGFloat = 12
    static let radius: CGFloat = 12
    static let sidebarWidth: CGFloat = 175
    static let previewRadius: CGFloat = 16
    static let visualTileRadius: CGFloat = 12
}
struct VisualSelectionTile<Content: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                content().frame(height: 64)
                HStack(spacing: 5) {
                    Text(title).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    Image(systemName: "checkmark.circle.fill").opacity(selected ? 1 : 0)
                        .foregroundStyle(QuotaClockColors.accent)
                }.font(.system(size: 12, weight: selected ? .semibold : .regular))
            }.frame(width: 120).padding(.vertical, 12)
                .background(selected ? QuotaClockColors.accentSelectedBackground : hovering ? QuotaClockColors.accentHover : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: SettingsTokens.visualTileRadius))
                .overlay(RoundedRectangle(cornerRadius: SettingsTokens.visualTileRadius)
                    .strokeBorder(selected ? QuotaClockColors.accentBorder : Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: SettingsTokens.visualTileRadius))
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
/// Vector miniatures stay crisp at every backing scale; Auto shares one scene
/// split down the middle so its light/dark relationship is immediately visible.
private struct AppearanceMiniature: View {
    let appearance: AppAppearance
    private func scene(dark: Bool) -> some View {
        let ink = dark ? Color.white : Color(red: 0.18, green: 0.17, blue: 0.15)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: dark ? [Color(red: 0.17, green: 0.19, blue: 0.23), Color(red: 0.31, green: 0.27, blue: 0.21)] : [Color(red: 0.87, green: 0.90, blue: 0.94), Color(red: 0.96, green: 0.89, blue: 0.74)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(QuotaClockColors.accent.opacity(0.22)).frame(width: 100).offset(x: 60, y: 22)
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.needle").font(.system(size: 7, weight: .semibold))
                BrandWordmark(size: 6)
                Spacer()
            }.padding(5).foregroundStyle(ink).background(ink.opacity(0.06))
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle").font(.system(size: 12))
                    RoundedRectangle(cornerRadius: 2).fill(QuotaClockColors.accent).frame(width: 16, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.18)).frame(width: 16, height: 3)
                    Spacer(minLength: 0)
                }.padding(.top, 9).frame(width: 29).background(ink.opacity(0.06))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { $0.frame(width: 3, height: 3).clipShape(Circle()) }
                    }
                    BrandWordmark(size: 7)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("84%").font(.system(size: 18, weight: .medium, design: .serif))
                        Image(systemName: "gauge.with.needle").font(.system(size: 10))
                    }
                    Capsule().fill(QuotaClockColors.accent).frame(height: 3).padding(.trailing, 8)
                }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
            }.foregroundStyle(ink).background(dark ? Color(white: 0.12) : Color(white: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 6)).shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .frame(width: 110, height: 70).offset(x: 12, y: 24)
        }.frame(width: 132, height: 92).clipped()
    }
    var body: some View {
        ZStack {
            scene(dark: appearance == .dark)
            if appearance == .system {
                scene(dark: true).mask { HStack(spacing: 0) { Color.clear; Color.black } }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
            .accessibilityHidden(true)
    }
}
struct AppearanceSelection: View {
    @ObservedObject var model: SnapshotController
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 14) {
            ForEach([AppAppearance.light, .dark, .system], id: \.self) { value in
                let selected = model.preferences.appearance == value
                Button {
                    var next = model.preferences; next.appearance = value; model.savePreferences(next)
                } label: {
                    VStack(spacing: 7) {
                        AppearanceMiniature(appearance: value)
                            .scaleEffect(compact ? 0.66 : 1)
                            .frame(width: compact ? 87 : 132, height: compact ? 61 : 92)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? QuotaClockColors.accent : .clear, lineWidth: 3))
                        Text(AppText.value(value == .system ? "Follow System" : value == .dark ? "Dark" : "Light", model.preferences.language))
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

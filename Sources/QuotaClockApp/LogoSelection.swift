import SwiftUI
import QuotaCore

struct LogoSelection: View {
    @ObservedObject var model: SnapshotController
    private func t(_ key: String) -> String { AppText.value(key, model.preferences.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.sectionTitleSpacing) {
            Text(t("App logo")).font(.system(size: 13, weight: .medium))
            HStack(spacing: SettingsTokens.controlGap) {
                ForEach(AppLogoStyle.allCases, id: \.self) { style in
                    VisualSelectionTile(title: t(style == .classic ? "Classic" : "Illuminated"), selected: model.platform.appLogo == style, action: {
                        var next = model.platform; next.appLogo = style; model.savePlatform(next)
                    }) { AppLogoView(style: style, size: 64) }
                }
            }
        }
    }
}

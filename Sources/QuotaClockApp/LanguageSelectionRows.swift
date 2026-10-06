import SwiftUI
import QuotaCore

/// Shared by the welcome guide and General settings, with trailing-aligned native controls.
struct LanguageSelectionRows: View {
    @ObservedObject var model: SnapshotController
    var detailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var language: AppLanguage { model.preferences.language }
    private func t(_ key: String) -> String { AppText.value(key, language) }
    private func title(_ choice: SurfaceLanguageSelection) -> String {
        switch choice {
        case .defaultEnglish: t("Default (English)")
        case .appLanguage: t("Same as App Language")
        default: choice.fixedLanguage!.nativeName
        }
    }
    private func surfacePicker(_ title: String, _ surface: DisplaySurface, _ value: AppLanguage) -> some View {
        HStack {
        Text(t(title)); Spacer()
        Picker(t(title), selection: Binding(get: { value }, set: {
            var next = model.preferences; next.setLanguage($0, for: surface); model.savePreferences(next)
        })) {
            ForEach(AppLanguage.allCases, id: \.self) { Text($0.nativeName).tag($0) }
        }.labelsHidden().fixedSize().accessibilityLabel(t(title))
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text(t("App language")).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Menu {
                    ForEach(AppLanguage.allCases, id: \.self) { choice in
                        Button {
                            var next = model.preferences; next.language = choice; model.savePreferences(next)
                        } label: {
                            if language == choice { Label(choice.nativeName, systemImage: "checkmark") }
                            else { Text(choice.nativeName) }
                        }
                    }
                } label: {
                    Text(language.nativeName)
                }.fixedSize().frame(width: 154, alignment: .trailing).accessibilityLabel(t("App language")).accessibilityValue(language.nativeName)
            }
            if detailed {
                Toggle(t("Follow App Language"), isOn: Binding(get: { model.preferences.followsAppLanguage }, set: {
                    var next = model.preferences; next.setFollowAppLanguage($0); model.savePreferences(next)
                }))
                if !model.preferences.followsAppLanguage {
                    VStack(spacing: 12) {
                        surfacePicker("Widget language", .widget, model.preferences.effectiveWidgetLanguage)
                        surfacePicker("Menu bar language", .menuBar, model.preferences.effectiveMenuLanguage)
                        surfacePicker("Screen saver language", .screenSaver, model.preferences.effectiveSaverLanguage)
                    }.transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
            HStack(spacing: 12) {
                Text(t("Surface Language")).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Menu {
                    ForEach(SurfaceLanguageSelection.allCases, id: \.self) { choice in
                        Button {
                            var next = model.preferences; next.selectSurfaceLanguage(choice); model.savePreferences(next)
                        } label: {
                            if model.preferences.displayedSurfaceLanguageSelection == choice {
                                Label(title(choice), systemImage: "checkmark")
                            } else { Text(title(choice)) }
                        }
                    }
                } label: {
                    Text(model.preferences.displayedSurfaceLanguageSelection.map(title) ?? t("Custom"))
                }.fixedSize().frame(width: 154, alignment: .trailing).accessibilityLabel(t("Surface Language"))
                    .accessibilityValue(model.preferences.displayedSurfaceLanguageSelection.map(title) ?? t("Custom"))
            }
            }
        }.font(.system(size: 13))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.preferences.followsAppLanguage)
    }
}

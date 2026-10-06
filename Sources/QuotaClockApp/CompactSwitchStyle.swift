import SwiftUI

/// Use the native small pill without shrinking the surrounding label typography.
struct CompactSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).controlSize(.mini)
    }
}

/// Settings rows keep a full-width label and align every switch to the trailing edge.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .fixedSize()
        }.frame(minHeight: 28)
    }
}

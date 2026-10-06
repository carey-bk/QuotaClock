import SwiftUI

/// Keep the provider identity and the user-assigned nickname visually distinct.
struct ProviderConnectionTitle: View {
    let name: String
    let nickname: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(name).font(.system(size: 13, weight: .semibold))
            if let nickname, !nickname.isEmpty {
                Text(nickname).font(.system(size: 13, weight: .medium, design: .serif)).italic()
            }
        }.lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name + (nickname.map { " " + $0 } ?? ""))
    }
}

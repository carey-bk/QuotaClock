import SwiftUI

/// Matches the website's ui-serif wordmark and terminal period on macOS.
struct BrandWordmark: View {
    var size: CGFloat = 26
    var body: some View {
        Text("QuotaClock.")
            .font(.system(size: size, weight: .regular, design: .serif))
            .tracking(-0.035 * size)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("QuotaClock")
    }
}

import SwiftUI
import QuotaCore

private final class ProviderAssetAnchor {}

/// One typographic identity for Menu Bar, Widgets, and Screen Saver/lock presentation.
struct ProviderAccountHeader: View {
    let provider: ProviderQuota?
    var titleSize: CGFloat = 14
    var scale: CGFloat = 1
    private var title: String { provider?.displayName ?? "QuotaClock" }
    private var signature: String? { provider?.nickname }
    private var asset: String? { ProviderCatalog.providers.first { $0.id == provider?.baseProviderID }?.asset }
    private var titleText: Text {
        if let signature {
            return Text("\(Text(title)) \(Text(signature).font(.system(size: titleSize * 0.50 * scale, design: .serif)).italic())")
        }
        return Text(title)
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5 * scale) {
            if let asset {
                Image(asset, bundle: Bundle(for: ProviderAssetAnchor.self))
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: titleSize * 0.78 * scale, height: titleSize * 0.78 * scale)
                    .accessibilityHidden(true)
            }
            titleText.font(.system(size: titleSize * scale, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.60)
        }.accessibilityElement(children: .ignore).accessibilityLabel(provider?.sourceTitle ?? title)
    }
}

import CoreGraphics
import Foundation

public enum MenuCardLayout {
    public static let width = 360.0
    public static let regularHeight = 170.0
    public static func height(large: Bool) -> Double { large ? width : regularHeight }
    public static func contentHeight(cards: Int, largeHero: Bool) -> Double {
        let count = max(0, min(8, cards))
        return Double(count) * (regularHeight + 12) + (largeHero && count > 0 ? width - regularHeight : 0)
    }
}

/// Geometry shared with the native panel: the account chooser has no vertical layout cost.
public struct MenuPanelLayout: Equatable {
    public let main: CGRect
    public let chooser: CGRect?
    public let cardHeight: Double
    public init(anchor: CGRect, screen: CGRect, alignment: MenuBarAlignment, cards: Int, accounts: Int,
                feedback: Bool, choosingAccount: Bool, largeHero: Bool = false) {
        let available = max(220, anchor.minY - screen.minY - 10)
        // Keep square cards intact; on short displays the cards scroll above a fixed footer.
        cardHeight = min(MenuCardLayout.contentHeight(cards: cards, largeHero: largeHero), max(70, available - 102))
        let height = min((cards == 0 ? (accounts == 0 ? 220.0 : 264.0) : cardHeight + 54) + (feedback ? 48 : 0), available)
        var x = alignment.origin(anchorMin: anchor.minX, anchorMax: anchor.maxX, width: 372, screenMin: screen.minX, screenMax: screen.maxX)
        if choosingAccount {
            // Shift only at the display edge, keeping the compact chooser fully to the left.
            x = max(x, screen.minX + 4 + 252 + 8)
            x = min(x, screen.maxX - 372 - 4)
        }
        main = CGRect(x: x, y: max(screen.minY + 4, anchor.minY - height - 6), width: 372, height: height)
        if choosingAccount {
            let chooserHeight = min(292, Double(accounts) * 38 + 110)
            chooser = CGRect(x: max(screen.minX + 4, x - 260),
                y: max(screen.minY + 4, min(main.minY + 4, screen.maxY - chooserHeight - 4)), width: 252, height: chooserHeight)
        } else { chooser = nil }
    }
}

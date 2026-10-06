import Foundation

public enum AmbientOrientation: String, Equatable, Sendable { case landscape, portrait }
public enum AmbientRailDensity: String, Equatable, Sendable { case hidden, medium, compact, square }

/// Coordinates use a top-left origin. Every saver instance calculates its own layout from bounds.
public struct AmbientRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public struct AmbientLayout: Equatable, Sendable {
    public var orientation: AmbientOrientation
    public var preview: Bool
    public var clock: AmbientRect
    public var hero: AmbientRect
    public var rail: AmbientRect?
    public var railDensity: AmbientRailDensity
    public var itemsPerPage: Int
    public var pageCount: Int
}
public enum AmbientLayoutEngine {
    public static func layout(width: Double, height: Double, providerCount: Int, preview: Bool = false) -> AmbientLayout {
        let w = max(1, width), h = max(1, height)
        let portrait = h > w * 1.15
        let isPreview = preview || (w < 480 && h < 360)
        let inset = isPreview ? max(10, min(w, h) * 0.045) : max(24, min(72, min(w, h) * 0.055))
        let gap = isPreview ? 10.0 : max(18, min(36, min(w, h) * 0.025))
        let contentW = min(w - 2 * inset, isPreview ? w : 1580)
        let x = (w - contentW) / 2
        let clockH = isPreview ? 0 : (portrait ? contentW * 0.28 : min(42, max(28, h * 0.055)))
        let top = inset + clockH + (clockH == 0 ? 0 : gap)
        let contentH = max(1, h - top - inset)
        let heroOnly = isPreview
        let clock = AmbientRect(x, inset, contentW, clockH)
        if heroOnly {
            let heroW = isPreview ? contentW : min(contentW, contentH, 940)
            let heroH = isPreview ? contentH : heroW
            return AmbientLayout(orientation: portrait ? .portrait : .landscape, preview: isPreview,
                clock: clock, hero: AmbientRect((w - heroW) / 2, top + (contentH - heroH) / 2, heroW, heroH), rail: nil,
                railDensity: .hidden, itemsPerPage: 0, pageCount: 0)
        }
        let count = min(2, max(0, providerCount - 1))
        if portrait {
            let heroW = max(1, min(contentW, (contentH - gap) / 1.62))
            let railW = heroW * 0.62
            return AmbientLayout(orientation: .portrait, preview: false, clock: clock,
                hero: AmbientRect((w - heroW) / 2, top, heroW, heroW),
                rail: AmbientRect((w - railW) / 2, top + heroW + gap, railW, railW),
                railDensity: count == 0 ? .hidden : .square, itemsPerPage: 1,
                pageCount: count == 0 ? 0 : 1)
        }
        let heroW = max(1, min(940, h * 0.82, (contentW - gap) / 1.58))
        let railW = max(1, min(460, heroW * 0.58, contentW - heroW - gap))
        let groupX = (w - heroW - gap - railW) / 2
        let heroY = (h - heroW) / 2
        let railH = count == 1 ? railW : min(heroW * 0.64, 2 * railW / 360 * 170 + 12)
        let railY = heroY + heroW - railH
        return AmbientLayout(orientation: .landscape, preview: false,
            clock: AmbientRect(groupX + heroW + gap, heroY, railW, max(1, railY - heroY - gap)),
            hero: AmbientRect(groupX, heroY, heroW, heroW),
            rail: AmbientRect(groupX + heroW + gap, railY, railW, railH),
            railDensity: count == 0 ? .hidden : count == 1 ? .square : .medium, itemsPerPage: count == 1 ? 1 : 2,
            pageCount: count == 0 ? 0 : 1)
    }
    /// Eight-point maximum drift; stable within each four-minute period.
    public static func burnInOffset(at date: Date, enabled: Bool) -> (x: Double, y: Double) {
        guard enabled else { return (0, 0) }
        let step = floor(date.timeIntervalSince1970 / 240)
        return (sin(step * 1.7) * 8, cos(step * 1.3) * 8)
    }
}

import AppKit
import SwiftUI
import QuotaCore

struct MenuBarStatusLabel: View {
    let snapshot: QuotaSnapshot?
    let language: AppLanguage
    var iconStyle: MenuBarIconStyle = .clock
    var showValue = true
    var gaugeColor: MenuBarGaugeColor = .monochrome
    var appearance: NSAppearance?
    private var reading: MenuBarIndicator { .init(snapshot: snapshot) }
    var body: some View {
        Image(nsImage: statusImage)
            .accessibilityLabel("\(reading.providerName) \(reading.text)")
            .help("\(reading.providerName) · \(reading.text)" + (reading.isStale ? " · \(AppText.value("STALE · LAST KNOWN VALUE", language))" : ""))
    }
    var statusImage: NSImage {
        let reading = reading
        let label = showValue && reading.providerID != nil ? reading.text : ""
        let asset = ProviderCatalog.providers.first { $0.id == reading.providerID }?.asset
        let logo = iconStyle == .provider ? asset.flatMap { NSImage(named: $0) } : nil
        let colored = logo == nil && gaugeColor == .color
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textSize = (label as NSString).size(withAttributes: [.font: font])
        let inset: CGFloat = 22
        let size = NSSize(width: label.isEmpty ? 18 : inset + ceil(textSize.width), height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // Resolve contrast in the menu bar's drawing appearance. Observing
            // effectiveAppearance creates a redraw loop while AppKit captures
            // status-item replicas in temporary light/dark appearances.
            let dark = (appearance ?? NSAppearance.currentDrawing()).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ink: NSColor = colored && dark ? .white : .black
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            if let logo {
                logo.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                Self.drawGauge(fraction: reading.fraction, colored: colored, ink: ink)
            }
            (label as NSString).draw(at: NSPoint(x: inset, y: (18 - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = !colored
        image.cacheMode = .never
        return image
    }
    /// Open 270-degree progress arc with a tapered pointer, drawn natively at
    /// every backing scale. Unknown/balance readings use a blue neutral gauge.
    static func drawGauge(fraction: Double?, colored: Bool, ink: NSColor) {
        let center = NSPoint(x: 9, y: 8.3), radius: CGFloat = 6.65
        let value = fraction.map { min(1, max(0, $0)) }
        let progress = value ?? 1
        func arc(_ end: CGFloat, _ color: NSColor) {
            color.setStroke()
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: end, clockwise: true)
            path.lineWidth = 2.25; path.lineCapStyle = .round; path.stroke()
        }
        arc(-45, ink.withAlphaComponent(0.25))
        let accent: NSColor
        if !colored { accent = ink }
        else if let value {
            accent = value < 0.3 ? NSColor(red: 0.95, green: 0.28, blue: 0.32, alpha: 1) :
                value < 0.7 ? NSColor(red: 0.98, green: 0.75, blue: 0.16, alpha: 1) :
                NSColor(red: 0.10, green: 0.85, blue: 0.56, alpha: 1)
        } else { accent = NSColor(red: 0.10, green: 0.48, blue: 1, alpha: 1) }
        if progress > 0 { arc(225 - 270 * progress, accent) }
        let angle = (225 - 270 * (value ?? 0.68)) * .pi / 180
        let direction = NSPoint(x: cos(angle), y: sin(angle))
        let perpendicular = NSPoint(x: -direction.y, y: direction.x)
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: center.x + direction.x * 4.7, y: center.y + direction.y * 4.7))
        pointer.line(to: NSPoint(x: center.x + perpendicular.x * 1.25, y: center.y + perpendicular.y * 1.25))
        pointer.line(to: NSPoint(x: center.x - perpendicular.x * 1.25, y: center.y - perpendicular.y * 1.25))
        pointer.close(); (colored && value == 0 ? accent : ink).setFill(); pointer.fill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.65, y: center.y - 1.65, width: 3.3, height: 3.3)).fill()
    }
}

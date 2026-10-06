import AppKit
import QuotaCore

@main struct RenderGaugeIcons {
    static func main() throws {
        _ = NSApplication.shared
        // The same non-template image must resolve text/needle contrast when
        // macOS draws it in a different appearance, without any KVO redraw loop.
        let adaptive = MenuBarStatusLabel(snapshot: nil, language: .english, showValue: false, gaugeColor: .color).statusImage
        func centerBrightness(_ appearance: NSAppearance.Name) -> CGFloat {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                adaptive.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            }
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.colorAt(x: 9, y: 9)!.usingColorSpace(.deviceRGB)!.redComponent
        }
        precondition(centerBrightness(.aqua) < 0.2)
        precondition(centerBrightness(.darkAqua) > 0.8)
        precondition(centerBrightness(.aqua) < 0.2)
        print("One native color icon adapts correctly through light -> dark -> light drawing appearances.")
        let width = 1120, height = 540
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        func text(_ value: String, x: CGFloat, y: CGFloat, color: NSColor, size: CGFloat = 13) {
            (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
        }
        NSColor(white: 0.94, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        text("QuotaClock · Gauge states · native 18 pt + enlarged detail", x: 32, y: 500, color: .black, size: 21)
        for (row, config) in [(false, MenuBarGaugeColor.monochrome), (true, .monochrome), (false, .color), (true, .color)].enumerated() {
            let (dark, mode) = config
            let y = CGFloat(370 - row * 112)
            let ink: NSColor = dark ? .white : .black
            (dark ? NSColor(white: 0.07, alpha: 1) : .white).setFill()
            NSBezierPath(roundedRect: NSRect(x: 24, y: y, width: 1072, height: 106), xRadius: 16, yRadius: 16).fill()
            text(mode == .color ? "Color" : "Monochrome", x: 40, y: y + 44, color: ink)
            for (col, percent) in [100.0, 84, 69, 45, 29, 10, 0, -1].enumerated() {
                let x = CGFloat(170 + col * 113)
                let snapshot: QuotaSnapshot?
                if percent < 0 { snapshot = nil }
                else { snapshot = QuotaSnapshot(generatedAt: .now, providers: [ProviderQuota(id: "codex", displayName: "Codex", planName: nil, limits: [.init(id: "5h", displayName: "5h", remainingPercentage: percent, isPrimary: true)], lastUpdated: .now)]) }
                let icon = MenuBarStatusLabel(snapshot: snapshot, language: .english, showValue: false, gaugeColor: mode,
                    appearance: NSAppearance(named: dark ? .darkAqua : .aqua)).statusImage
                // Template pixels are black by definition. Resolve their alpha to
                // the requested menu background in this stand-alone proof sheet.
                let resolved = NSImage(size: icon.size)
                resolved.lockFocus(); icon.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                if icon.isTemplate { ink.setFill(); NSRect(origin: .zero, size: icon.size).fill(using: .sourceIn) }
                resolved.unlockFocus()
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform(); transform.translateX(by: x, yBy: y + 28); transform.scale(by: 48 / 18); transform.concat()
                MenuBarStatusLabel.drawGauge(fraction: percent < 0 ? nil : percent / 100, colored: mode == .color, ink: ink)
                NSGraphicsContext.restoreGraphicsState()
                resolved.draw(in: NSRect(x: x + 60, y: y + 42, width: 18, height: 18))
                text(percent < 0 ? "No quota" : "\(Int(percent))%", x: x + 10, y: y + 8, color: ink, size: 11)
                precondition(icon.isTemplate == (mode == .monochrome))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("32 native gauge states rendered; template/color modes verified.")
    }
}

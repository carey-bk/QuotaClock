import AppKit

// Installer artwork is rendered from vectors at 1x and 2x for Retina Finder windows.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800 * scale, pixelsHigh: 600 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(scale)); transform.concat()
    let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
    NSGradient(colors: [NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.94, alpha: 1), .white,
                        NSColor(calibratedRed: 0.92, green: 0.87, blue: 0.76, alpha: 1)])!.draw(in: bounds, angle: -25)
    func text(_ string: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (string as NSString).draw(at: NSPoint(x: x, y: 600 - top - font.ascender - 4), withAttributes: attrs)
    }
    let ink = NSColor(calibratedWhite: 0.16, alpha: 1)
    let secondary = NSColor(calibratedWhite: 0.43, alpha: 1)
    let gold = NSColor(calibratedRed: 0.65, green: 0.52, blue: 0.31, alpha: 1)
    text("QuotaClock", x: 54, top: 36, size: 30, weight: .semibold, color: ink)
    text("1. 拖入 Applications，安装主应用", x: 54, top: 91, size: 22, weight: .medium, color: ink)
    text("Drag QuotaClock into Applications to install", x: 54, top: 123, size: 14, color: secondary)
    // Finder places the two draggable, 128-point native icons above these guide wells.
    NSColor.white.withAlphaComponent(0.48).setFill()
    for x: CGFloat in [125, 505] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 277, width: 170, height: 170), xRadius: 34, yRadius: 34).fill()
    }
    gold.setStroke()
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 342, y: 362)); arrow.line(to: NSPoint(x: 458, y: 362))
    arrow.move(to: NSPoint(x: 443, y: 374)); arrow.line(to: NSPoint(x: 458, y: 362)); arrow.line(to: NSPoint(x: 443, y: 350))
    arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    NSColor(calibratedWhite: 0.2, alpha: 0.12).setStroke()
    let rule = NSBezierPath(); rule.move(to: NSPoint(x: 54, y: 216)); rule.line(to: NSPoint(x: 746, y: 216)); rule.lineWidth = 1; rule.stroke()
    text("2. 安装屏幕保护程序", x: 272, top: 417, size: 20, weight: .medium, color: ink)
    text("双击左侧 QuotaClock.saver，按系统提示安装。", x: 272, top: 453, size: 15, color: secondary)
    text("Double-click QuotaClock.saver to install.", x: 272, top: 481, size: 13, color: secondary)
    text("完成后，可推出此磁盘。  Eject this disk when finished.", x: 54, top: 560, size: 12, color: secondary)
    NSGraphicsContext.restoreGraphicsState()
    let path = output.appendingPathComponent(scale == 1 ? "installer.png" : "installer@2x.png")
    try rep.representation(using: .png, properties: [:])!.write(to: path)
}

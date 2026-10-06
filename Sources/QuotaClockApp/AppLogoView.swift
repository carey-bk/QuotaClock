import SwiftUI
import AppKit
import ImageIO
import QuotaCore

/// Decode at the destination's backing-pixel size rather than minifying a
/// 1254-pixel GPU texture. This preserves the thin dial and transparent rim.
struct AppLogoView: View {
    let style: AppLogoStyle
    let size: CGFloat
    @Environment(\.displayScale) private var scale
    private static let cache = NSCache<NSString, NSImage>()

    private var image: NSImage {
        let name = style == .classic ? "LogoClassic" : "LogoGlow"
        let pixels = Int(ceil(size * scale))
        let key = "\(name)-\(pixels)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let original = NSImage(named: name) ?? NSImage()
        guard let data = original.tiffRepresentation,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return original }
        let result = NSImage(cgImage: bitmap, size: NSSize(width: size, height: size))
        Self.cache.setObject(result, forKey: key)
        return result
    }
    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high)
            .scaledToFit().frame(width: size, height: size)
            .accessibilityLabel("QuotaClock")
    }
}

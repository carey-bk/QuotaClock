import AppKit
import SwiftUI
import WidgetKit
import QuotaCore

@main struct WidgetAppearanceProof {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var provider = ProviderQuota(id: "codex", displayName: "Codex", planName: "Plus", limits: [
            .init(id: "5h", displayName: "5-hour", remainingPercentage: 72, isPrimary: true),
            .init(id: "week", displayName: "Weekly", remainingPercentage: 64)
        ], lastUpdated: .now, bankResetCount: 2)
        provider.account = .init(id: UUID(), signature: "Studio")
        for (modeName, mode) in [("color", WidgetRenderingMode.fullColor), ("system", .accented)] {
            for (appearance, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                for (name, family, size) in [("small", WidgetFamily.systemSmall, CGSize(width: 170, height: 170)),
                                           ("medium", .systemMedium, CGSize(width: 360, height: 170)),
                                           ("large", .systemLarge, CGSize(width: 360, height: 360))] {
                    let content = WidgetCardContent(provider: provider, family: family, language: .english, renderingMode: mode)
                        .background {
                            if mode == .fullColor { WidgetCardBackground() }
                            else { RoundedRectangle(cornerRadius: 22).fill(scheme == .dark ? Color(white: 0.14) : Color(white: 0.92)) }
                        }
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: content); renderer.scale = 2
                    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("render failed") }
                    if mode == .fullColor {
                        // Sample a clear area of the archived background, away from text and rounded edges.
                        let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 6)!.usingColorSpace(.deviceRGB)!
                        precondition(color.alphaComponent > 0.99)
                        precondition(max(color.redComponent, color.greenComponent, color.blueComponent) < 0.35)
                    }
                    try png.write(to: output.appendingPathComponent("widget-\(modeName)-\(appearance)-\(name).png"))
                }
            }
        }
        print("PASS: shared widget content rendered in 3 sizes × light/dark × full-color/system palette. Full-color backgrounds remain opaque and dark in all 6 samples. System WidgetKit tint compositor is not simulated.")
    }
}

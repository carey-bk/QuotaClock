import AppKit
import SwiftUI
import QuotaCore

/// A static gallery cover rendered with the real screen saver. All values are illustrative.
@main struct SaverThumbnail {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9, minute: 41))!
        func provider(_ name: String, _ value: Double, _ weekly: Double) -> ProviderQuota {
            let account = AccountPresentation(id: UUID(), signature: name)
            var result = ProviderQuota(id: "codex", displayName: "Codex", planName: "Plus", limits: [
                .init(id: "5h", displayName: "5-hour", remainingPercentage: value, isPrimary: true),
                .init(id: "week", displayName: "Weekly", remainingPercentage: weekly)
            ], lastUpdated: date)
            var product = ProductMigration.product(result); product.account = account
            product.id = "codex.subscription.account." + account.id.uuidString.lowercased()
            result.id = product.sourceID; result.products = [product]; result.account = account
            return result
        }
        var providers = [provider("Studio", 82, 74), provider("Personal", 68, 92), provider("Work", 47, 60)]
        providers[0].account?.isCurrent = true
        providers[0].products?[0].account?.isCurrent = true
        var snapshot = QuotaSnapshot(generatedAt: date, providers: providers)
        var platform = PlatformPreferences()
        platform.surfaces = .init(menu: providers.map(\.id), hero: providers[0].id, secondary: Array(providers.dropFirst().map(\.id)))
        snapshot.platformPreferences = platform
        var preferences = AmbientPreferences(); preferences.showClock = true; preferences.showDate = false
        let content = AmbientDisplay(snapshot: snapshot, preferences: preferences, now: date, page: 0, preview: false, accelerated: false, allowsMotion: false)
            .frame(width: 1602, height: 972).environment(\.colorScheme, .dark)
        for (name, scale) in [("thumbnail.png", 534.0 / 1602), ("thumbnail@2x.png", 1068.0 / 1602)] {
            let renderer = ImageRenderer(content: content); renderer.scale = scale
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("thumbnail render failed") }
            try data.write(to: output.appendingPathComponent(name))
            print("Rendered \(name): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
        }
    }
}

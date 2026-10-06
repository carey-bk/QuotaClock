import AppKit
import SwiftUI
import QuotaCore

/// Shared card content and exact menu sizes, using a fixed background for deterministic renders.
@main struct MenuHeroProof {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_791_187_200)
        let cards = ["Studio", "Work", "Personal"].enumerated().map { index, name in
            var provider = ProviderQuota(id: "codex", displayName: "Codex", planName: "Plus", limits: [
                .init(id: "5h", displayName: "5-hour", remainingPercentage: [54, 67, 87][index], resetAt: date.addingTimeInterval(18000), isPrimary: true),
                .init(id: "week", displayName: "Weekly", remainingPercentage: [30, 67, 40][index])
            ], lastUpdated: date, bankResetCount: 2,
                usage: .init(totalTokens: 412_800_000, peakDailyTokens: 82_000_000, lastDailyTokens: 18_800_000,
                    dailyHistory: [29, 34, 21, 58, 82, 47, 18].enumerated().map { offset, value in
                        UsageDay(date: date.addingTimeInterval(Double(offset - 6) * 86400), tokens: Int64(value) * 1_000_000)
                    }))
            provider.account = .init(id: UUID(), signature: name)
            return provider
        }
        for language in [AppLanguage.english, .chinese] {
            for largeHero in [false, true] {
                let content = VStack(spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, provider in
                        let large = largeHero && index == 0
                        ProviderCard(provider: provider, density: large ? .full : .medium, drawsPanel: false, language: language)
                            .frame(width: MenuCardLayout.width, height: MenuCardLayout.height(large: large))
                            .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.13, green: 0.14, blue: 0.15)))
                    }
                }
                .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: content); renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("render failed") }
                precondition(bitmap.pixelsWide == 720)
                precondition(bitmap.pixelsHigh == (largeHero ? 1448 : 1068))
                try data.write(to: output.appendingPathComponent("hero-\(largeHero ? "large" : "regular")-\(language.rawValue).png"))
            }
        }
        print("PASS: shared menu cards rendered in English/Chinese, regular and square Hero, with full quota/history content at 2x. Other cards remain 360×170. These content renders do not simulate live glass compositing.")
    }
}

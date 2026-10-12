import AppKit
import SwiftUI
import WidgetKit
import QuotaCore

@main struct LargeCodexProof {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .chinese] {
            let cards = [67.0, 59, 0].enumerated().map { index, percent in
                var p = ProviderQuota(id: "codex", displayName: "Codex", planName: index == 0 ? "Plus" : "Pro 5x", limits: [
                    .init(id: "5h", displayName: "5-hour", remainingPercentage: percent,
                          resetAt: Date(timeIntervalSince1970: 1791643500), windowDuration: 18000, isPrimary: true),
                    .init(id: "week", displayName: "Weekly", remainingPercentage: 29)
                ], lastUpdated: .now, bankResetCount: index == 1 ? 12 : 2)
                if index > 0 {
                    p.limits = [.init(id: "codex.primary", displayName: "Weekly", remainingPercentage: percent,
                                     resetAt: Date(timeIntervalSince1970: 1791975240), windowDuration: 604800, isPrimary: true)]
                }
                p.usage = .init(totalTokens: 5_470_000_000, peakDailyTokens: 301_500_000, lastDailyTokens: 51_600_000,
                    dailyHistory: (0..<7).map { UsageDay(date: Date(timeIntervalSince1970: 1791500000).addingTimeInterval(Double($0) * 86400), tokens: Int64($0 + 1) * 20_000_000) })
                p.account = .init(id: UUID(), signature: index == 0 ? "Hanz" : "Carey")
                return p
            }
            let content = VStack(alignment: .leading, spacing: 12) {
                Text("SAMPLE DATA · 360 × 360 pt").font(.system(size: 11)).foregroundStyle(.gray)
                HStack(spacing: 16) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, provider in
                        WidgetCardContent(provider: provider, family: .systemLarge, language: language, renderingMode: .fullColor)
                            .frame(width: 360, height: 360).background(WidgetCardBackground())
                    }
                }
            }.padding(20).background(Color(white: 0.06)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content); renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("render failed") }
            try data.write(to: output.appendingPathComponent("codex-large-\(language.rawValue).png"))
        }
    }
}

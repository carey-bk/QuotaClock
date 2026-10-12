import AppKit
import SwiftUI
import QuotaCore

/// Synthetic response fixtures only. No credentials, network, settings, or snapshot publishing.
@main struct SubscriptionProof {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = root.appendingPathComponent("Evidence/claude-research-20261010/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var normal = try ClaudeQuotaParser.parse(Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Claude/usage-fable.json")), at: .now)
        normal.planName = "Max 5x" // Synthetic preview metadata, never production.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let tokens: [Int64] = [12_500_000, 19_800_000, 15_300_000, 39_800_000, 30_700_000, 12_800_000, 12_100_000]
        normal.usage = UsageStatistics(totalTokens: 328_700_000, peakDailyTokens: 39_800_000, lastDailyTokens: 12_100_000, dailyHistory: tokens.enumerated().map { index, value in
            UsageDay(date: calendar.date(byAdding: .day, value: index - 7, to: today)!, tokens: value)
        }) // Synthetic token history for layout only; never inferred from subscription percentages.
        var pro = normal
        pro.planName = "Pro"; pro.bankResetCount = 1
        var max20 = normal
        max20.planName = "Max 20x"
        var noHistory = normal
        noHistory.usage = nil
        var exhausted = normal
        exhausted.limits[0].remainingPercentage = 0
        var fresh = normal
        fresh.limits[0].remainingPercentage = 100
        var stale = normal
        stale.health = ProviderHealth(state: .stale, lastSuccess: Date().addingTimeInterval(-1800), usingLastKnownGood: true)
        var missing = ProviderQuota(id: "claude-code", displayName: "Claude", planName: nil, limits: [], lastUpdated: .now)
        missing.health = ProviderHealth(state: .authenticationRequired)
        var kimi = normal
        kimi.id = "kimi"; kimi.displayName = "Kimi"; kimi.limits = Array(kimi.limits.prefix(2))
        kimi.limits[0].displayName = "5-hour"; kimi.limits[1].displayName = "Weekly"
        var single = normal
        single.limits = [normal.limits[0]]; single.limits[0].resetAt = nil
        var many = normal
        many.limits.append(.init(id: "future-scope", displayName: "An unusually long model name Weekly", remainingPercentage: 45, resetAt: nil))
        var noFable = normal
        noFable.limits.removeAll { $0.id.hasPrefix("weekly_scoped.") }; noFable.planName = "Pro"
        noFable.claudeExtraUsage = .init(enabled: false)
        var noResets = normal
        noResets.bankResetCount = nil
        let cases = [("normal", normal), ("pro", pro), ("max20", max20), ("no-history", noHistory), ("no-resets", noResets), ("exhausted", exhausted), ("fresh", fresh), ("stale", stale), ("no-account", missing), ("template-kimi", kimi), ("single-no-reset", single), ("many-scopes", many), ("no-fable", noFable)]
        for language in [AppLanguage.english, .chinese] {
            for (name, provider) in cases {
                let view = VStack(alignment: .leading, spacing: 18) {
                    Text("SAMPLE DATA / 示例数据 · \(name)").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    HStack(alignment: .top, spacing: 20) {
                        card(provider, .full, 360, 360, language)
                        VStack(alignment: .leading, spacing: 20) {
                            card(provider, .medium, 360, 170, language)
                            card(provider, .compact, 170, 170, language)
                        }
                    }
                }.padding(24).background(Color(white: 0.075)).environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view); renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("render failed") }
                try png.write(to: output.appendingPathComponent("\(name)-\(language.rawValue).png"))
            }
        }
        print("Rendered 26 bilingual fixture sheets (78 cards); no production data changed.")
    }
    @MainActor static func card(_ provider: ProviderQuota, _ density: ProviderCardDensity, _ width: CGFloat, _ height: CGFloat, _ language: AppLanguage) -> some View {
        ProviderCard(provider: provider, density: density, drawsPanel: false, language: language)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.15)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }
}

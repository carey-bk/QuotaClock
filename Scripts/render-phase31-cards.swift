import AppKit
import SwiftUI
import QuotaCore

@main struct RenderCards {
  @MainActor static func main() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_790_359_200)
    let days = (0..<7).map { UsageDay(date: now.addingTimeInterval(Double($0 - 6) * 86400),
                                          tokens: Int64([12, 23, 36, 29, 54, 76, 42][$0]) * 1_000_000) }
    let codex = ProviderQuota(id: "codex", displayName: "Codex", planName: "Pro 5x",
      limits: [LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: 29,
                           resetAt: now.addingTimeInterval(4 * 86400), windowDuration: 604_800, isPrimary: true)],
      lastUpdated: now, bankResetCount: 1,
      usage: UsageStatistics(totalTokens: 4_134_524_195, peakDailyTokens: 301_547_668,
                             lastDailyTokens: 74_540_484, dailyHistory: days))
    var dualCodex = codex
    dualCodex.planName = "Plus"
    dualCodex.limits = [LimitWindow(id: "5h", displayName: "5-hour", remainingPercentage: 77,
                                    resetAt: now.addingTimeInterval(5400), windowDuration: 18_000, isPrimary: true),
                        LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: 18)]
    let deepseek = ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [],
      lastUpdated: now, balances: [BalanceAmount(currency: "CNY", total: 4.88, granted: 0, toppedUp: 4.88)], balanceAvailable: true)
    var claude = ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: nil, limits: [], lastUpdated: now)
    claude.health = ProviderHealth(state: .authenticationRequired)
    var stale = codex
    stale.health = ProviderHealth(state: .stale, lastSuccess: now.addingTimeInterval(-3600), usingLastKnownGood: true)
    var zero = codex
    zero.limits[0].remainingPercentage = 0
    var full = codex
    full.limits[0].remainingPercentage = 100
    var long = codex
    long.id = "long-provider"
    long.displayName = "Extremely Long Provider Name"
    long.planName = "Experimental Long Plan"
    long.limits[0].displayName = "Extended Weekly Limit Name"
    var largeBalance = deepseek
    largeBalance.balances = [BalanceAmount(currency: "CNY", total: 1_234_567.89, granted: 0, toppedUp: 1_234_567.89)]
    let cases: [(String, ProviderQuota, ProviderCardDensity, Int, Int, AppLanguage)] = [
      ("codex-small", codex, .compact, 170, 170, .english),
      ("codex-medium", codex, .medium, 360, 170, .english),
      ("codex-large", codex, .full, 360, 360, .english),
      ("codex-desktop-small", codex, .compact, 120, 120, .english),
      ("codex-desktop-medium", codex, .medium, 250, 120, .english),
      ("codex-desktop-large", codex, .full, 250, 250, .english),
      ("codex-dual-small", dualCodex, .compact, 170, 170, .english),
      ("codex-dual-desktop-small", dualCodex, .compact, 120, 120, .english),
      ("codex-dual-small-zh", dualCodex, .compact, 170, 170, .chinese),
      ("codex-dual-medium", dualCodex, .medium, 360, 170, .english),
      ("codex-dual-large", dualCodex, .full, 360, 360, .english),
      ("deepseek-small", deepseek, .compact, 170, 170, .english),
      ("deepseek-medium", deepseek, .medium, 360, 170, .english),
      ("deepseek-large", deepseek, .full, 360, 360, .english),
      ("deepseek-desktop-small", deepseek, .compact, 120, 120, .english),
      ("deepseek-desktop-medium", deepseek, .medium, 250, 120, .english),
      ("deepseek-desktop-large", deepseek, .full, 250, 250, .english),
      ("claude-small", claude, .compact, 170, 170, .english),
      ("claude-medium", claude, .medium, 360, 170, .english),
      ("claude-large", claude, .full, 360, 360, .english),
      ("claude-desktop-small", claude, .compact, 120, 120, .english),
      ("claude-desktop-medium", claude, .medium, 250, 120, .english),
      ("codex-stale", stale, .medium, 360, 170, .english),
      ("codex-zero", zero, .compact, 170, 170, .english),
      ("codex-full", full, .full, 360, 360, .english),
      ("codex-long", long, .medium, 360, 170, .english),
      ("deepseek-large-balance", largeBalance, .full, 360, 360, .english),
      ("deepseek-large-balance-small", largeBalance, .compact, 170, 170, .english),
      ("deepseek-large-balance-medium", largeBalance, .medium, 360, 170, .english),
      ("codex-chinese", codex, .full, 360, 360, .chinese),
      ("codex-chinese-small", codex, .compact, 170, 170, .chinese),
      ("codex-chinese-medium", codex, .medium, 360, 170, .chinese),
      ("codex-chinese-desktop-small", codex, .compact, 120, 120, .chinese),
      ("codex-chinese-desktop-medium", codex, .medium, 250, 120, .chinese),
      ("codex-chinese-desktop-large", codex, .full, 250, 250, .chinese)
    ]
    let localized: [(String, ProviderQuota, ProviderCardDensity, Int, Int, AppLanguage)] = AppLanguage.allCases.flatMap { language in
      [("locale-\(language.rawValue)-small", dualCodex, .compact, 170, 170, language),
       ("locale-\(language.rawValue)-medium", dualCodex, .medium, 360, 170, language),
       ("locale-\(language.rawValue)-large", dualCodex, .full, 360, 360, language)]
    }
    for (name, provider, density, w, h, language) in cases + localized {
      let base = density == .compact ? CGSize(width: 170, height: 170) :
        density == .medium ? CGSize(width: 360, height: 170) : CGSize(width: 360, height: 360)
      let scale = min(CGFloat(w) / base.width, CGFloat(h) / base.height)
      let view = ProviderCard(provider: provider, density: density, language: language, layoutScale: scale)
        .frame(width: CGFloat(w), height: CGFloat(h))
      let renderer = ImageRenderer(content: view)
      renderer.scale = 1
      guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError(name) }
      try data.write(to: output.appendingPathComponent(name + ".png"))
    }
  }
}

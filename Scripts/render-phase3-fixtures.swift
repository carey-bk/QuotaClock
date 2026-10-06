import AppKit
import SwiftUI
import QuotaCore

@main struct Render {
  @MainActor static func main() throws {
    let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_790_359_200)
    let days = (0..<7).map { UsageDay(date: now.addingTimeInterval(Double($0 - 6) * 86400),
                                          tokens: Int64([45, 75, 3, 168, 190, 75, 42][$0]) * 1_000_000) }
    let codex = ProviderQuota(id: "codex", displayName: "Codex", planName: "Pro 5x", limits: [
      LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: 29,
                  resetAt: now.addingTimeInterval(4 * 86400), windowDuration: 604_800, isPrimary: true)],
      lastUpdated: now, bankResetCount: 1,
      usage: UsageStatistics(totalTokens: 4_134_524_195, peakDailyTokens: 301_547_668,
                             lastDailyTokens: 74_540_484, dailyHistory: days))
    let deepseek = ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [], lastUpdated: now,
      balances: [BalanceAmount(currency: "CNY", total: 4.90, granted: 0, toppedUp: 4.90)], balanceAvailable: true)
    var singleDay = codex
    singleDay.usage = UsageStatistics(totalTokens: 9800000, peakDailyTokens: 9800000, lastDailyTokens: 9800000, dailyHistory: [UsageDay(date: now, tokens: 9800000)])
    var stale = codex
    stale.health = ProviderHealth(state: .stale, lastSuccess: now.addingTimeInterval(-3600), usingLastKnownGood: true)
    var claude = ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: nil, limits: [], lastUpdated: now)
    claude.health = ProviderHealth(state: .authenticationRequired)
    let cases: [(String, Int, Int, [ProviderQuota], String?)] = [
      ("single-day", 960, 540, [singleDay, deepseek], nil),
      ("landscape-one", 960, 540, [codex], nil),
      ("landscape-two", 960, 540, [codex, deepseek], nil),
      ("landscape-fullhd", 1920, 1080, [codex, deepseek], nil),
      ("landscape-four", 960, 540, [codex, deepseek, claude, codexCopy(codex, id:"fourth")], nil),
      ("landscape-16x10", 800, 500, [codex, deepseek], nil),
      ("ultrawide", 1280, 360, [codex, deepseek, claude], nil),
      ("super-ultrawide", 1280, 360, [codex, deepseek, claude, codexCopy(codex, id:"fourth")], nil),
      ("portrait", 540, 960, [codex, deepseek, claude], nil),
      ("portrait-four", 540, 960, [codex, deepseek, claude, codexCopy(codex, id:"fourth")], nil),
      ("balance", 960, 540, [deepseek, codex], "deepseek"),
      ("stale", 960, 540, [stale, deepseek], nil),
      ("authentication", 960, 540, [claude, codex], "claude-code"),
      ("preview", 360, 240, [codex, deepseek], nil),
    ]
    for (name, w, h, providers, pinned) in cases {
      for language in [AppLanguage.english, .chinese] {
      var snapshot = QuotaSnapshot(generatedAt: now, providers: providers)
      snapshot.heroSelection = .pinned(providerID: pinned ?? providers[0].id)
      var preferences = AmbientPreferences(); preferences.language = language
      let view = AmbientDisplay(snapshot: snapshot, preferences: preferences, now: now, page: 0, preview: name == "preview", accelerated: false)
        .frame(width: CGFloat(w), height: CGFloat(h))
      let renderer = ImageRenderer(content: view)
      renderer.scale = 1
      guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("render \(name)") }
      let suffix = language == .english ? "" : "-chinese"
      try data.write(to: out.appendingPathComponent("\(name)\(suffix).png"))
      }
    }
  }
  static func codexCopy(_ source: ProviderQuota, id: String) -> ProviderQuota {
    ProviderQuota(id: id, displayName: "Provider 4", planName: nil, limits: source.limits, lastUpdated: source.lastUpdated)
  }
}

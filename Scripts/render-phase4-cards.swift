import AppKit
import SwiftUI
import QuotaCore

/// Synthetic presentation fixtures only; this executable has no publisher or transport.
@main struct Phase4Cards {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_790_467_200)
        let code = ProductQuota(id: "kimi.code", providerID: "kimi", displayName: "Kimi Code", meters: [
            Meter(id: "plan", displayName: "Current plan quota", kind: .percentageQuota, value: 64, resetAt: date.addingTimeInterval(86400), updatedAt: date, reliability: .providerSupportedUndocumented)
        ], at: date, planName: "Sample plan")
        let api = ProductQuota(id: "kimi.api", providerID: "kimi", displayName: "Kimi Open Platform", meters: [
            Meter(id: "balance.CNY", displayName: "API Balance", kind: .balance, value: 88.20, currency: "CNY", updatedAt: date, reliability: .officialPublicAPI)
        ], at: date)
        var hybrid = ProviderQuota(id: "kimi", displayName: "Kimi", planName: nil, limits: [], lastUpdated: date)
        hybrid.products = [code, api]; hybrid = hybrid.selecting()
        var cases: [(String, ProviderQuota)] = [("hybrid-quota", hybrid), ("hybrid-balance", hybrid.selecting(productID: "kimi.api"))]
        var deepseek = ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [], lastUpdated: date)
        deepseek.products = [ProductQuota(id: "deepseek.api", providerID: "deepseek", displayName: "DeepSeek API", meters: [
            Meter(id: "balance.CNY", displayName: "Balance", kind: .balance, value: 4.88, currency: "CNY", updatedAt: date, reliability: .officialPublicAPI),
            Meter(id: "local.today.tokens", displayName: "Usage Today · DSH", kind: .usage, value: 1234567, unit: "tokens", resetAt: .distantFuture, primaryEligible: false, updatedAt: date, reliability: .communityVerified),
            Meter(id: "local.today.cny", displayName: "Estimated CNY · DSH", kind: .spend, value: 1.23, currency: "CNY", resetAt: .distantFuture, primaryEligible: false, updatedAt: date, reliability: .communityVerified)
        ], at: date)]
        cases.append(("deepseek-today", deepseek.selecting()))
        for (kind, value, unit) in [(MeterKind.credits, Decimal(12450), "credits"), (.usage, Decimal(3200000), "tokens"), (.spend, Decimal(string: "15.09")!, "CNY"), (.absoluteQuota, Decimal(1200), "requests")] {
            var provider = ProviderQuota(id: "sample", displayName: "Sample Product", planName: nil, limits: [], lastUpdated: date)
            provider.products = [ProductQuota(id: "sample.product", providerID: "sample", displayName: "Sample Product", meters: [
                Meter(id: kind.rawValue, displayName: kind == .usage ? "This month" : kind.rawValue, kind: kind, value: value,
                      unit: unit, currency: kind == .spend ? "CNY" : nil, updatedAt: date, reliability: .officialLocalState)
            ], at: date)]
            cases.append((kind.rawValue, provider.selecting()))
        }
        var observed = ProviderQuota(id: "custom.fixture", displayName: "Responses Compatible Long Provider Name", planName: nil, limits: [], lastUpdated: date)
        observed.products = [ProductQuota(id: "custom.fixture.responses", providerID: observed.id, displayName: observed.displayName, meters: [
            Meter(id: "observed.day.tokens", displayName: "Observed Today", kind: .usage, value: 3240000, unit: "tokens", updatedAt: date, reliability: .officialLocalState),
            Meter(id: "observed.week.tokens", displayName: "Observed This Week", kind: .usage, value: 10240000, unit: "tokens", updatedAt: date, reliability: .officialLocalState),
            Meter(id: "observed.month.tokens", displayName: "Observed This Month", kind: .usage, value: 50100000, unit: "tokens", updatedAt: date, reliability: .officialLocalState)
        ], at: date)]
        cases.append(("observed", observed.selecting()))
        for (name, provider) in cases {
          for language in [AppLanguage.english, .chinese] {
            for (density, width, height, suffix) in [(ProviderCardDensity.compact, 120.0, 120.0, "small"), (.medium, 250, 120, "medium"), (.full, 250, 250, "large")] {
                let base = density == .compact ? 170.0 : 360.0
                let view = ProviderCard(provider: provider, density: density, saverPanel: true, language: language, layoutScale: width / base)
                    .frame(width: width, height: height)
                let renderer = ImageRenderer(content: view); renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("render") }
                try data.write(to: output.appendingPathComponent("\(name)-\(suffix)-\(language.rawValue).png"))
            }
          }
        }
    }
}

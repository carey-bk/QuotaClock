import Foundation
import CoreFoundation

/// DSH's local daily ledger, not account-wide billing. No prompts or credentials are read.
public enum DeepSeekLocalUsage {
    public static func meters(data: Data, at date: Date, calendar: Calendar = .current) throws -> [Meter] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == 1, let days = root["days"] as? [String: Any] else { throw ProviderFetchError.invalidResponse }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        guard let providers = days[day] as? [String: Any],
              let models = providers["deepseek-official"] as? [String: [String: Any]], !models.isEmpty else { return [] }
        var tokens: Decimal = 0, spend: Decimal = 0
        var priced = true
        for (model, row) in models {
            func number(_ key: String) throws -> Decimal {
                guard let n = row[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                      n.doubleValue.isFinite, n.doubleValue >= 0 else { throw ProviderFetchError.invalidResponse }
                guard let value = Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX")) else { throw ProviderFetchError.invalidResponse }
                return value
            }
            // DSH input excludes cache; reasoning is already included in output.
            for key in ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"] {
                let n = try number(key)
                guard NSDecimalNumber(decimal: n).doubleValue.rounded() == NSDecimalNumber(decimal: n).doubleValue else { throw ProviderFetchError.invalidResponse }
                tokens += n
            }
            // The installed ledger's Pro price schedule is outdated. Do not reuse it.
            if ["deepseek-flash", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp"].contains(model) {
                spend += try number("cost")
            } else { priced = false }
        }
        guard tokens <= Decimal(Int64.max) else { throw ProviderFetchError.invalidResponse }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        var result = [Meter(id: "local.today.tokens", displayName: "Usage Today · DSH", kind: .usage,
            value: tokens, unit: "tokens", resetAt: end, primaryEligible: false, updatedAt: date, reliability: .communityVerified)]
        if priced { result.append(Meter(id: "local.today.cny", displayName: "Estimated CNY · DSH", kind: .spend,
            value: spend, currency: "CNY", resetAt: end, primaryEligible: false, updatedAt: date, reliability: .communityVerified)) }
        return result
    }
    public static func read(at date: Date) -> [Meter] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/dsh-usage/usage-ledger.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 10_000_000,
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? meters(data: data, at: date)) ?? []
    }
}

public struct DeepSeekProductAdapter: ProductAdapter {
    public let descriptor = ProviderCatalog.product("deepseek.api")
    private let balance: DeepSeekProviderAdapter
    public init(credential: @escaping @Sendable () -> String?) { balance = DeepSeekProviderAdapter(credential: credential) }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        var product = ProductMigration.product(try await balance.fetchQuota(at: date), descriptor: descriptor)
        product.meters += DeepSeekLocalUsage.read(at: date)
        return product
    }
}

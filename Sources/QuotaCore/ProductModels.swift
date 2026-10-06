import Foundation

public enum MeterKind: String, Codable, CaseIterable, Sendable {
    case percentageQuota, absoluteQuota, balance, usage, spend, credits
}
public enum SourceReliability: String, Codable, Sendable {
    case officialPublicAPI, officialCLI, officialLocalState, providerSupportedUndocumented, communityVerified, unsupported
}
public extension SourceReliability {
    var displayName: String {
        switch self {
        case .officialPublicAPI: "Official public API"
        case .officialCLI: "Official CLI"
        case .officialLocalState: "Local recorded data"
        case .providerSupportedUndocumented: "Provider-supported undocumented API"
        case .communityVerified: "Community-verified source"
        case .unsupported: "Source not verified"
        }
    }
}
public struct Meter: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var kind: MeterKind
    public var value: Decimal
    public var total: Decimal?
    public var remaining: Decimal?
    public var unit: String?
    public var currency: String?
    public var resetAt: Date?
    public var windowDuration: TimeInterval?
    public var primaryEligible: Bool
    public var updatedAt: Date
    public var reliability: SourceReliability
    public init(id: String, displayName: String, kind: MeterKind, value: Decimal, total: Decimal? = nil,
                remaining: Decimal? = nil, unit: String? = nil, currency: String? = nil, resetAt: Date? = nil,
                windowDuration: TimeInterval? = nil, primaryEligible: Bool = true, updatedAt: Date,
                reliability: SourceReliability) {
        self.id = id; self.displayName = displayName; self.kind = kind; self.value = value
        self.total = total; self.remaining = remaining; self.unit = unit; self.currency = currency
        self.resetAt = resetAt; self.windowDuration = windowDuration; self.primaryEligible = primaryEligible
        self.updatedAt = updatedAt; self.reliability = reliability
    }
    public func validated() throws -> Self {
        guard !id.isEmpty, !displayName.isEmpty, !value.isNaN, value >= 0,
              total.map({ !$0.isNaN && $0 >= 0 }) ?? true,
              remaining.map({ !$0.isNaN && $0 >= 0 }) ?? true,
              windowDuration.map({ $0.isFinite && $0 > 0 }) ?? true else { throw ProviderFetchError.invalidResponse }
        if kind == .percentageQuota && value > 100 { throw ProviderFetchError.invalidResponse }
        if let total, let remaining, remaining > total { throw ProviderFetchError.invalidResponse }
        if kind == .balance || kind == .spend {
            guard let currency, currency.count == 3, currency.allSatisfy({ $0.isASCII && $0.isUppercase }) else { throw ProviderFetchError.invalidResponse }
        }
        return self
    }
    public var formattedValue: String {
        if kind == .percentageQuota { return QuotaFormat.percentage(NSDecimalNumber(decimal: value).doubleValue) }
        if kind == .usage && unit == "tokens" {
            let number = NSDecimalNumber(decimal: value).doubleValue
            for (threshold, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] where number >= threshold {
                return String(format: "%.2f%@", number / threshold, suffix)
            }
        }
        let f = NumberFormatter()
        if let currency {
            f.numberStyle = .currency; f.currencyCode = currency
            f.locale = Locale(identifier: currency == "CNY" ? "zh_CN" : "en_US")
            f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        } else { f.numberStyle = .decimal; f.maximumFractionDigits = 2 }
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    public var label: String {
        switch kind {
        case .percentageQuota, .absoluteQuota: return "Remaining"
        case .balance: return "Balance"
        case .credits: return "Credits Remaining"
        case .usage: return unit == "tokens" ? "Tokens Used" : "Usage"
        case .spend: return "Spent"
        }
    }
}

/// Presentation-only product state. Profile identifiers and credentials never belong here.
public struct ProductQuota: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var providerID: String
    public var displayName: String
    public var planName: String?
    public var meters: [Meter]
    public var defaultMeterID: String?
    public var health: ProviderHealth?
    public var metricChangedAt: Date
    public var bankResetCount: Int?
    public var usage: UsageStatistics?
    public var balances: [BalanceAmount]?
    public var balanceAvailable: Bool?
    public var account: AccountPresentation?
    public init(id: String, providerID: String, displayName: String, meters: [Meter], at: Date,
                defaultMeterID: String? = nil, planName: String? = nil) {
        self.id = id; self.providerID = providerID; self.displayName = displayName; self.meters = meters
        self.defaultMeterID = defaultMeterID; self.planName = planName; self.metricChangedAt = at
    }
    public func validated() throws -> Self {
        guard !id.isEmpty, !providerID.isEmpty, !displayName.isEmpty,
              Set(meters.map(\.id)).count == meters.count else { throw ProviderFetchError.invalidResponse }
        if let account, !ProviderAccount.validSignature(account.signature) { throw ProviderFetchError.invalidResponse }
        for meter in meters { _ = try meter.validated() }
        return self
    }
    public func primary(_ choice: String? = nil) -> Meter? {
        let eligible = meters.filter(\.primaryEligible)
        return eligible.first { $0.id == choice } ?? eligible.first { $0.id == defaultMeterID } ?? eligible.first
    }
}
public protocol ProductAdapter: Sendable {
    var descriptor: ProductDescriptor { get }
    var minimumRefreshInterval: TimeInterval { get }
    func fetchProduct(at date: Date) async throws -> ProductQuota
}
public extension ProductAdapter {
    /// Adapters may impose a longer endpoint-specific minimum.
    var minimumRefreshInterval: TimeInterval { 30 }
}
public struct ProductDescriptor: Identifiable, Sendable {
    public var id: String
    public var providerID: String
    public var displayName: String
    public var reliability: SourceReliability
    public var connection: String
    public var supported: Bool { reliability != .unsupported }
}
public struct ProviderDescriptor: Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var asset: String?
}
public enum ProviderCatalog {
    public static let providers: [ProviderDescriptor] = [
        .init(id: "codex", displayName: "Codex", asset: "ProviderOpenAI"),
        .init(id: "claude-code", displayName: "Claude Code", asset: "ProviderClaude"),
        .init(id: "deepseek", displayName: "DeepSeek", asset: "ProviderDeepSeek"),
        .init(id: "glm", displayName: "GLM / Zhipu", asset: "ProviderGLM"),
        .init(id: "kimi", displayName: "Kimi", asset: "ProviderKimi"),
        .init(id: "bailian", displayName: "Qwen / Bailian", asset: "ProviderQwen")
    ]
    public static let products: [ProductDescriptor] = [
        .init(id: "codex.subscription", providerID: "codex", displayName: "Codex Subscription", reliability: .officialCLI, connection: "local"),
        .init(id: "claude-code.subscription", providerID: "claude-code", displayName: "Claude Code Subscription", reliability: .providerSupportedUndocumented, connection: "local"),
        .init(id: "deepseek.api", providerID: "deepseek", displayName: "DeepSeek API", reliability: .officialPublicAPI, connection: "key"),
        .init(id: "glm.coding-plan", providerID: "glm", displayName: "GLM Coding Plan", reliability: .providerSupportedUndocumented, connection: "key"),
        .init(id: "glm.api", providerID: "glm", displayName: "GLM Standard API", reliability: .unsupported, connection: "unsupported"),
        .init(id: "kimi.code", providerID: "kimi", displayName: "Kimi Code", reliability: .providerSupportedUndocumented, connection: "key"),
        .init(id: "kimi.extra-usage", providerID: "kimi", displayName: "Kimi Extra Usage", reliability: .unsupported, connection: "unsupported"),
        .init(id: "kimi.api", providerID: "kimi", displayName: "Kimi Open Platform (China)", reliability: .officialPublicAPI, connection: "key"),
        .init(id: "kimi.api-international", providerID: "kimi", displayName: "Kimi Open Platform (International)", reliability: .officialPublicAPI, connection: "key"),
        .init(id: "bailian.coding-plan", providerID: "bailian", displayName: "Bailian Coding Plan", reliability: .officialCLI, connection: "cli"),
        .init(id: "bailian.token-plan", providerID: "bailian", displayName: "Bailian Token Plan", reliability: .officialCLI, connection: "cli"),
        .init(id: "bailian.paygo", providerID: "bailian", displayName: "Bailian Pay-as-you-go API", reliability: .unsupported, connection: "unsupported")
    ]
    public static func name(_ id: String) -> String { providers.first { $0.id == id }?.displayName ?? id }
    public static func product(_ id: String) -> ProductDescriptor { products.first { $0.id == id }! }
    public static func legacyProductID(_ providerID: String) -> String { providerID + (providerID == "deepseek" ? ".api" : ".subscription") }
}

/// Transitional boundary for proven Phase 1/2 parsers. New sources implement ProductAdapter directly.
public struct LegacyProductAdapter: ProductAdapter {
    private let adapter: any ProviderAdapter
    public let descriptor: ProductDescriptor
    public init(_ adapter: any ProviderAdapter) {
        self.adapter = adapter
        descriptor = ProviderCatalog.products.first { $0.id == ProviderCatalog.legacyProductID(adapter.providerID) } ??
            ProductDescriptor(id: ProviderCatalog.legacyProductID(adapter.providerID), providerID: adapter.providerID,
                              displayName: adapter.providerID, reliability: .officialLocalState, connection: "local")
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        let quota = try await adapter.fetchQuota(at: date)
        guard quota.id == descriptor.providerID else { throw ProviderFetchError.invalidResponse }
        _ = try QuotaSnapshot(generatedAt: date, providers: [quota]).validated()
        return ProductMigration.product(quota, descriptor: descriptor)
    }
}
public enum ProductMigration {
    public static func product(_ old: ProviderQuota, descriptor: ProductDescriptor? = nil) -> ProductQuota {
        let definition = descriptor ?? ProviderCatalog.products.first { $0.id == ProviderCatalog.legacyProductID(old.id) }
        let reliability = definition?.reliability ?? .officialLocalState
        var meters = old.limits.map { Meter(id: $0.id, displayName: $0.displayName, kind: .percentageQuota,
            value: Decimal($0.remainingPercentage), resetAt: $0.resetAt, windowDuration: $0.windowDuration,
            updatedAt: old.lastUpdated, reliability: reliability) }
        meters += (old.balances ?? []).map { Meter(id: "balance.\($0.currency)", displayName: "Balance", kind: .balance,
            value: $0.total, currency: $0.currency, updatedAt: old.lastUpdated, reliability: reliability) }
        var product = ProductQuota(id: definition?.id ?? ProviderCatalog.legacyProductID(old.id), providerID: old.id,
            displayName: definition?.displayName ?? old.displayName, meters: meters, at: old.quotaChangedAt,
            defaultMeterID: old.primaryLimit?.id ?? old.primaryBalance.map { "balance.\($0.currency)" }, planName: old.planName)
        product.health = old.health; product.bankResetCount = old.bankResetCount; product.usage = old.usage
        product.balances = old.balances; product.balanceAvailable = old.balanceAvailable
        return product
    }
}

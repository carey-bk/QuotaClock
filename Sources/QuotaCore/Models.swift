import Foundation

public struct LimitWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// Provider-authored terminology; never derived from duration.
    public var displayName: String
    public var remainingPercentage: Double
    public var resetAt: Date?
    public var windowDuration: TimeInterval?
    public var isPrimary: Bool
    public init(id: String, displayName: String, remainingPercentage: Double, resetAt: Date? = nil, windowDuration: TimeInterval? = nil, isPrimary: Bool = false) {
        self.id = id; self.displayName = displayName; self.remainingPercentage = remainingPercentage
        self.resetAt = resetAt; self.windowDuration = windowDuration; self.isPrimary = isPrimary
    }
}
public struct UsageDay: Codable, Equatable, Sendable {
    public var date: Date
    public var tokens: Int64
    public init(date: Date, tokens: Int64) { self.date = date; self.tokens = tokens }
}
public struct UsageStatistics: Codable, Equatable, Sendable {
    public var totalTokens: Int64?
    public var peakDailyTokens: Int64?
    public var lastDailyTokens: Int64?
    public var dailyHistory: [UsageDay]?
    public init(totalTokens: Int64? = nil, peakDailyTokens: Int64? = nil,
                lastDailyTokens: Int64? = nil, dailyHistory: [UsageDay]? = nil) {
        self.totalTokens = totalTokens; self.peakDailyTokens = peakDailyTokens
        self.lastDailyTokens = lastDailyTokens; self.dailyHistory = dailyHistory
    }
}
public struct BalanceAmount: Codable, Equatable, Sendable {
    public var currency: String
    public var total: Decimal
    public var granted: Decimal?
    public var toppedUp: Decimal?
    public init(currency: String, total: Decimal, granted: Decimal? = nil, toppedUp: Decimal? = nil) {
        self.currency = currency; self.total = total; self.granted = granted; self.toppedUp = toppedUp
    }
    public func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: currency == "CNY" ? "zh_CN" : "en_US")
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currency) \(amount)"
    }
}
public struct ProviderQuota: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var planName: String?
    public var limits: [LimitWindow]
    public var lastUpdated: Date
    public var quotaChangedAt: Date
    public var bankResetCount: Int?
    public var usage: UsageStatistics?
    public var balances: [BalanceAmount]?
    public var balanceAvailable: Bool?
    public var health: ProviderHealth?
    public var products: [ProductQuota]?
    public var displayPreference: ProviderDisplayPreference?
    public var account: AccountPresentation?
    public var primaryLimit: LimitWindow? { limits.first(where: \.isPrimary) ?? limits.first }
    public var primaryBalance: BalanceAmount? { balances?.first(where: { $0.currency == "CNY" }) ?? balances?.first }
    public var hasMetric: Bool { products != nil ? primaryMeter != nil : (primaryLimit != nil || primaryBalance != nil) }
    public init(id: String, displayName: String, planName: String?, limits: [LimitWindow], lastUpdated: Date, quotaChangedAt: Date? = nil, bankResetCount: Int? = nil, usage: UsageStatistics? = nil, balances: [BalanceAmount]? = nil, balanceAvailable: Bool? = nil) {
        self.id = id; self.displayName = displayName; self.planName = planName; self.limits = limits
        self.lastUpdated = lastUpdated; self.quotaChangedAt = quotaChangedAt ?? lastUpdated
        self.bankResetCount = bankResetCount; self.usage = usage; self.balances = balances; self.balanceAvailable = balanceAvailable
    }
}
public enum ProviderHealthState: String, Codable, Sendable {
    case healthy, stale, authenticationRequired, unavailable, rateLimited, error
    public var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .stale: return "Stale"
        case .authenticationRequired: return "Authentication required"
        case .unavailable: return "Unavailable"
        case .rateLimited: return "Rate limited"
        case .error: return "Error"
        }
    }
}
public struct ProviderHealth: Codable, Equatable, Sendable {
    public var state: ProviderHealthState
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var reason: String?
    public var usingLastKnownGood: Bool
    public init(state: ProviderHealthState, lastAttempt: Date? = nil, lastSuccess: Date? = nil, reason: String? = nil, usingLastKnownGood: Bool = false) {
        self.state = state; self.lastAttempt = lastAttempt; self.lastSuccess = lastSuccess
        self.reason = reason; self.usingLastKnownGood = usingLastKnownGood
    }
}
public enum HeroSelection: Codable, Equatable, Sendable {
    case automatic
    case pinned(providerID: String)
}
public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision: UUID
    public var generatedAt: Date
    public var providers: [ProviderQuota]
    public var heroSelection: HeroSelection = .automatic
    public var platformPreferences: PlatformPreferences?
    public var hero: ProviderQuota? {
        if platformPreferences?.providerDisplay != nil { return providersInDisplayOrder.first }
        if followsCurrentCodexAccount { return currentCodexHero }
        if case let .pinned(id) = effectiveHeroSelection {
            if let pinned = providers.first(where: { $0.id == id }) { return pinned }
            if platformPreferences?.surfaces != nil {
                var missing = ProviderQuota(id: id, displayName: ProviderCatalog.name(id), planName: nil, limits: [], lastUpdated: generatedAt)
                missing.health = ProviderHealth(state: .unavailable, reason: "Selected account unavailable")
                return missing
            }
        }
        let automatic = providers.enumerated().filter { $0.element.hasMetric && ($0.element.displayPreference?.heroEligible ?? true) }.max {
            $0.element.quotaChangedAt == $1.element.quotaChangedAt ? $0.offset > $1.offset : $0.element.quotaChangedAt < $1.element.quotaChangedAt
        }?.element
        if automatic?.baseProviderID == "codex", platformPreferences?.codexMultiAccount == true { return currentCodexHero }
        return automatic
    }
    public init(revision: UUID = UUID(), generatedAt: Date, providers: [ProviderQuota]) {
        self.revision = revision; self.generatedAt = generatedAt; self.providers = providers
    }
    public func displayProjection() -> Self { DisplaySnapshot(from: self).value }
    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw SnapshotError.unsupportedVersion(schemaVersion) }
        guard Set(providers.map(\.id)).count == providers.count else { throw SnapshotError.invalidData }
        for provider in providers {
            if let account = provider.account {
                guard ProviderAccount.validSignature(account.signature),
                      provider.id == DisplaySourceID.make(provider: provider.baseProviderID, account: account.id),
                      provider.products?.allSatisfy({ $0.account == account }) == true else { throw SnapshotError.invalidData }
            }
            if let products = provider.products {
                guard Set(products.map(\.id)).count == products.count else { throw SnapshotError.invalidData }
                for product in products {
                    guard product.providerID == provider.baseProviderID, product.sourceID == provider.id else { throw SnapshotError.invalidData }
                    _ = try product.validated()
                }
            }
            guard !provider.id.isEmpty, !provider.displayName.isEmpty,
                  Set(provider.limits.map(\.id)).count == provider.limits.count,
                  provider.limits.filter(\.isPrimary).count <= 1 else { throw SnapshotError.invalidData }
            for limit in provider.limits {
                guard !limit.id.isEmpty, !limit.displayName.isEmpty, limit.remainingPercentage.isFinite,
                      (0...100).contains(limit.remainingPercentage),
                      limit.windowDuration.map({ $0.isFinite && $0 > 0 }) ?? true else { throw SnapshotError.invalidData }
            }
            if let balances = provider.balances {
                guard !balances.isEmpty, Set(balances.map(\.currency)).count == balances.count else { throw SnapshotError.invalidData }
                for balance in balances {
                    guard ["CNY", "USD"].contains(balance.currency), balance.total >= 0,
                          balance.granted.map({ $0 >= 0 }) ?? true,
                          balance.toppedUp.map({ $0 >= 0 }) ?? true else { throw SnapshotError.invalidData }
                }
            }
        }
        return self
    }
    public mutating func setRemaining(providerID: String, limitID: String, value: Double, now: Date = Date()) throws {
        guard value.isFinite, (0...100).contains(value),
              let p = providers.firstIndex(where: { $0.id == providerID }),
              let l = providers[p].limits.firstIndex(where: { $0.id == limitID }) else { throw SnapshotError.invalidData }
        if providers[p].limits[l].remainingPercentage != value { providers[p].quotaChangedAt = now }
        providers[p].limits[l].remainingPercentage = value
        providers[p].lastUpdated = now
        generatedAt = now; revision = UUID()
    }
}
/// Explicit allowlist for the ordinary-file screen-saver export. Its wire shape stays
/// QuotaSnapshot-compatible so existing macOS saver hosts can read across an app update.
public struct DisplaySnapshot: Sendable {
    public let value: QuotaSnapshot
    public init(from canonical: QuotaSnapshot) {
        let providers = canonical.providers.map { source -> ProviderQuota in
            let limits = source.limits.map {
                LimitWindow(id: $0.id, displayName: $0.displayName,
                    remainingPercentage: $0.remainingPercentage, resetAt: $0.resetAt,
                    windowDuration: nil, isPrimary: $0.isPrimary)
            }
            var safe = ProviderQuota(id: source.id, displayName: source.displayName,
                planName: source.planName, limits: limits,
                lastUpdated: source.lastUpdated, quotaChangedAt: source.quotaChangedAt,
                bankResetCount: source.bankResetCount,
                usage: source.usage.map { usage in
                    UsageStatistics(totalTokens: usage.totalTokens,
                        peakDailyTokens: usage.peakDailyTokens,
                        lastDailyTokens: usage.lastDailyTokens,
                        dailyHistory: usage.dailyHistory.map { Array($0.suffix(7)) })
                }, balances: source.balances,
                balanceAvailable: source.balanceAvailable)
            if let health = source.health {
                safe.health = ProviderHealth(state: health.state, lastSuccess: health.lastSuccess,
                    reason: health.reason == nil ? nil : health.state.displayName, usingLastKnownGood: health.usingLastKnownGood)
            }
            safe.account = source.account
            safe.displayPreference = source.displayPreference
            safe.products = source.products?.map { product in
                var clean = ProductQuota(id: product.id, providerID: product.providerID, displayName: product.displayName,
                    meters: product.meters.map { meter in
                        Meter(id: meter.id, displayName: meter.displayName, kind: meter.kind, value: meter.value,
                              total: meter.total, remaining: meter.remaining, unit: meter.unit, currency: meter.currency,
                              resetAt: meter.resetAt, primaryEligible: meter.primaryEligible, updatedAt: meter.updatedAt,
                              reliability: meter.reliability)
                    }, at: product.metricChangedAt, defaultMeterID: product.defaultMeterID, planName: product.planName)
                if let health = product.health {
                    clean.health = ProviderHealth(state: health.state, lastSuccess: health.lastSuccess,
                        usingLastKnownGood: health.usingLastKnownGood)
                }
                clean.account = product.account
                clean.bankResetCount = product.bankResetCount
                clean.usage = product.usage.map { UsageStatistics(totalTokens: $0.totalTokens, peakDailyTokens: $0.peakDailyTokens,
                    lastDailyTokens: $0.lastDailyTokens, dailyHistory: $0.dailyHistory.map { Array($0.suffix(7)) }) }
                clean.balances = product.balances; clean.balanceAvailable = product.balanceAvailable
                return clean
            }
            return safe
        }
        var safe = QuotaSnapshot(revision: canonical.revision, generatedAt: canonical.generatedAt, providers: providers)
        safe.heroSelection = canonical.heroSelection
        safe.platformPreferences = canonical.platformPreferences
        value = safe
    }
}
public enum SnapshotError: Error, LocalizedError {
    case unsupportedVersion(Int), invalidData, groupUnavailable
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Unsupported snapshot schema: \(version)"
        case .invalidData: return "Invalid quota snapshot (percentages must be 0–100)."
        case .groupUnavailable: return "App Group unavailable. Check signing and entitlements."
        }
    }
}
public enum QuotaFormat {
    public static func percentage(_ value: Double) -> String { String(format: "%.0f%%", value) }
}
/// Only the main app's coordinator invokes adapters. Surfaces are snapshot readers.
public protocol ProviderAdapter: Sendable {
    var providerID: String { get }
    func fetchQuota(at date: Date) async throws -> ProviderQuota
}

import SwiftUI
import QuotaCore

// Preview-only fixtures. This view is never used as a production snapshot source.
private enum CardFixtures {
    static func quota(_ remaining: Double, name: String = "Codex", plan: String? = "Plus", history: Bool = false) -> ProviderQuota {
        ProviderQuota(id: "codex", displayName: name, planName: plan,
            limits: [LimitWindow(id: "5h", displayName: "5-hour", remainingPercentage: remaining, resetAt: .now.addingTimeInterval(7200), isPrimary: true),
                     LimitWindow(id: "week", displayName: "Weekly", remainingPercentage: 36)],
            lastUpdated: .now, bankResetCount: 2,
            usage: history ? UsageStatistics(totalTokens: 288_200_000, dailyHistory: nil) : nil)
    }
    static var deepSeek: ProviderQuota {
        ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [], lastUpdated: .now,
            balances: [BalanceAmount(currency: "CNY", total: 4.90, granted: 0, toppedUp: 4.90)], balanceAvailable: true)
    }
    static var claudeAuth: ProviderQuota {
        var quota = ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: nil, limits: [], lastUpdated: .now)
        quota.health = ProviderHealth(state: .authenticationRequired)
        return quota
    }
}

#Preview("Large · Codex 19%") { ProviderCard(provider: CardFixtures.quota(19, history: true), density: .full).frame(width: 340, height: 360) }
#Preview("Medium · Codex") { ProviderCard(provider: CardFixtures.quota(74), density: .medium).frame(width: 360, height: 170) }
#Preview("Small · DeepSeek") { ProviderCard(provider: CardFixtures.deepSeek, density: .compact).frame(width: 170, height: 170) }
#Preview("Auth required") { ProviderCard(provider: CardFixtures.claudeAuth, density: .medium).frame(width: 360, height: 170) }
#Preview("Long names") { ProviderCard(provider: CardFixtures.quota(100, name: "Provider With A Very Long Name", plan: "Long Experimental Plan"), density: .compact).frame(width: 170, height: 170) }
#Preview("Zero remaining") { ProviderCard(provider: CardFixtures.quota(0), density: .compact).frame(width: 170, height: 170) }
#Preview("Full remaining") { ProviderCard(provider: CardFixtures.quota(100), density: .full).frame(width: 340, height: 360) }
#Preview("DeepSeek · medium") { ProviderCard(provider: CardFixtures.deepSeek, density: .medium).frame(width: 360, height: 170) }

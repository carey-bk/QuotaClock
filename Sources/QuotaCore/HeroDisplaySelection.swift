import Foundation

public extension HeroSelection {
    /// Keep the existing wire format. Old account pins become the Codex family pin.
    var followingCodexLogin: Self {
        if case let .pinned(id) = self, id.hasPrefix("codex.account.") { return .pinned(providerID: "codex") }
        return self
    }
}

public extension QuotaSnapshot {
    var followsCurrentCodexAccount: Bool {
        guard platformPreferences?.providerDisplay == nil else { return false }
        guard platformPreferences?.codexMultiAccount == true else { return false }
        return effectiveHeroSelection.followingCodexLogin == .pinned(providerID: "codex")
    }
    var currentCodexHero: ProviderQuota {
        if let current = providers.first(where: { $0.baseProviderID == "codex" && $0.account?.isCurrent == true }) { return current }
        // Never present a previous account as the current login after logout, hiding or removal.
        var missing = ProviderQuota(id: "codex", displayName: "Codex", planName: nil, limits: [], lastUpdated: generatedAt)
        missing.health = ProviderHealth(state: .unavailable, reason: "Current Codex account unavailable")
        return missing
    }
}

/// Shared by the Widget extension and tests; an explicit Hero always wins over old metric choices.
public enum WidgetDisplaySelection {
    public static let heroID = "quotaclock.hero"

    public static func provider(in snapshot: QuotaSnapshot, sourceID: String?, metric: [String]?, legacyProviderID: String? = nil) -> ProviderQuota? {
        func unavailable(_ reason: String, id: String = "unavailable", name: String = "QuotaClock") -> ProviderQuota {
            var value = ProviderQuota(id: id, displayName: name, planName: nil, limits: [], lastUpdated: snapshot.generatedAt)
            value.health = ProviderHealth(state: .unavailable, reason: reason)
            return value
        }
        func hero() -> ProviderQuota? {
            // Resolve the canonical Hero before surface filtering, so a hidden Hero cannot
            // silently become a different provider in the Widget.
            guard let chosen = snapshot.hero else { return nil }
            guard snapshot.platformPreferences?.providerDisplay != nil || snapshot.platformPreferences?.surfaces != nil || (chosen.displayPreference ?? .init()).availableInWidgets else { return unavailable("Hero unavailable in Widgets") }
            return chosen
        }
        if sourceID == heroID { return hero() }
        let visible = snapshot.forSurface(.widget)
        if let sourceID {
            guard let provider = visible.providers.first(where: { $0.id == sourceID }) else { return unavailable("Selected account unavailable") }
            if let metric, metric.count == 3, metric[0] == sourceID,
               provider.activeProducts.contains(where: { $0.id == metric[1] && $0.meters.contains(where: { $0.id == metric[2] && $0.primaryEligible }) }) {
                return provider.selecting(productID: metric[1], meterID: metric[2])
            }
            return provider
        }
        // Preserve older Widget configurations that selected only a metric or legacy provider.
        if let metric {
            if metric.count == 3, let provider = visible.providers.first(where: { $0.id == metric[0] }),
               provider.activeProducts.contains(where: { $0.id == metric[1] && $0.meters.contains(where: { $0.id == metric[2] && $0.primaryEligible }) }) {
                return provider.selecting(productID: metric[1], meterID: metric[2])
            }
            return unavailable("Selected product or metric unavailable")
        }
        if let id = legacyProviderID {
            return visible.providers.first { $0.id == id } ?? unavailable("Provider is disabled", id: id, name: ProviderCatalog.name(id))
        }
        return hero()
    }
}

import Foundation

/// One provider queue feeds every automatic display. Legacy per-surface pins
/// remain decodable, but are ignored once this configuration is present.
public struct ProviderDisplayConfiguration: Codable, Equatable, Sendable {
    public var heroProviderID: String?
    public var autoHero: Bool
    public var menuLimit: Int
    public var saverLimit: Int
    public var effectiveMenuLimit: Int { min(8, max(1, menuLimit)) }
    public var effectiveSaverLimit: Int { min(3, max(2, saverLimit)) }
    public init(autoHero: Bool = true, menuLimit: Int = 3, saverLimit: Int = 3, heroProviderID: String? = nil) {
        self.heroProviderID = heroProviderID
        self.autoHero = autoHero; self.menuLimit = menuLimit; self.saverLimit = saverLimit
    }
    private enum CodingKeys: String, CodingKey { case autoHero, menuLimit, saverLimit, heroProviderID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(autoHero: try c.decodeIfPresent(Bool.self, forKey: .autoHero) ?? true,
                  menuLimit: try c.decodeIfPresent(Int.self, forKey: .menuLimit) ?? 3,
                  saverLimit: try c.decodeIfPresent(Int.self, forKey: .saverLimit) ?? 3,
                  heroProviderID: try c.decodeIfPresent(String.self, forKey: .heroProviderID))
    }
}

public extension QuotaSnapshot {
    var providersInConnectionOrder: [ProviderQuota] {
        let ids = platformPreferences?.connectionOrder ?? []
        let known = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        var seen = Set<String>()
        return (ids + providers.map(\.id)).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return known[id]
        }
    }
    /// Follow the logged-in account within the chosen provider family. Never
    /// substitute another saved account when the current login is unavailable.
    var automaticDisplayHero: ProviderQuota? {
        let ordered = providersInConnectionOrder
        let selected = platformPreferences?.providerDisplay?.heroProviderID
        let family = ordered.first(where: { $0.baseProviderID == selected })?.baseProviderID ?? ordered.first?.baseProviderID
        let candidates = ordered.filter { $0.baseProviderID == family }
        guard let first = candidates.first else { return nil }
        if let current = candidates.first(where: { $0.account?.isCurrent == true }) { return current }
        if !candidates.contains(where: { $0.account != nil }) { return first }
        var missing = ProviderQuota(id: first.baseProviderID, displayName: first.displayName, planName: nil, limits: [], lastUpdated: generatedAt)
        missing.health = .init(state: .unavailable, reason: "Current account unavailable")
        return missing
    }
    var providersInDisplayOrder: [ProviderQuota] {
        let ordered = providersInConnectionOrder
        guard platformPreferences?.providerDisplay?.autoHero == true,
              let chosen = automaticDisplayHero else { return ordered }
        return [chosen] + ordered.filter { $0.id != chosen.id }
    }

}

public extension MeterKind {
    var drivesAutoHero: Bool {
        switch self {
        case .percentageQuota, .absoluteQuota, .balance, .credits: true
        case .usage, .spend: false
        }
    }
}

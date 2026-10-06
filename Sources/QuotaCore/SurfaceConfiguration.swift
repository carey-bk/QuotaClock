import Foundation

/// Display choices belong to their surface, never to connection settings.
/// Empty strings reserve optional slots; a Hero is always required.
public struct SurfaceConfiguration: Codable, Equatable, Sendable {
    public var menu: [String]
    public var hero: String
    public var secondary: [String]
    public init(menu: [String] = [], hero: String = "codex", secondary: [String] = []) {
        self.menu = Self.slots(menu, count: 3)
        self.hero = hero.isEmpty ? "codex" : hero
        self.secondary = Self.slots(secondary, count: 2)
    }
    private enum CodingKeys: String, CodingKey { case menu, hero, secondary }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(menu: try c.decodeIfPresent([String].self, forKey: .menu) ?? [],
                  hero: try c.decodeIfPresent(String.self, forKey: .hero) ?? "codex",
                  secondary: try c.decodeIfPresent([String].self, forKey: .secondary) ?? [])
    }
    public static func slots(_ ids: [String], count: Int) -> [String] {
        var result: [String] = []
        for id in ids.prefix(count) { result.append(id.isEmpty || result.contains(id) ? "" : id) }
        return result + Array(repeating: "", count: max(0, count - result.count))
    }
    public mutating func setMenu(_ id: String, at index: Int) {
        guard (0..<3).contains(index) else { return }
        menu = Self.slots(menu, count: 3)
        for i in menu.indices where i != index && menu[i] == id { menu[i] = "" }
        menu[index] = id
    }
    public mutating func setSecondary(_ id: String, at index: Int) {
        guard (0..<2).contains(index) else { return }
        secondary = Self.slots(secondary, count: 2)
        for i in secondary.indices where i != index && secondary[i] == id { secondary[i] = "" }
        secondary[index] = id
    }
    public static func migrating(_ snapshot: QuotaSnapshot) -> Self {
        let chosen = snapshot.hero ?? snapshot.providers.first
        let heroID = chosen?.baseProviderID == "codex" ? "codex" : chosen?.id ?? "codex"
        return Self(menu: Array(snapshot.forSurface(.menuBar).providers.prefix(3).map(\.id)), hero: heroID,
                    secondary: Array(snapshot.forSurface(.screenSaver).providers.filter { $0.id != chosen?.id }.prefix(2).map(\.id)))
    }
}
public extension QuotaSnapshot {
    func saverSecondaryProviders(portrait: Bool) -> [ProviderQuota] {
        if let display = platformPreferences?.providerDisplay {
            return Array(forSurface(.screenSaver).providers.dropFirst().prefix(portrait ? 1 : display.effectiveSaverLimit - 1))
        }
        if let selections = platformPreferences?.surfaces {
            let ids = portrait ? Array(selections.secondary.prefix(1)) : Array(selections.secondary.prefix(2))
            return ids.compactMap { id in providers.first { $0.id == id && $0.id != hero?.id } }
        }
        return Array(forSurface(.screenSaver).providers.filter { $0.id != hero?.id }.prefix(portrait ? 1 : 2))
    }
    var effectiveHeroSelection: HeroSelection {
        platformPreferences?.surfaces.map { .pinned(providerID: $0.hero) } ?? heroSelection
    }
}

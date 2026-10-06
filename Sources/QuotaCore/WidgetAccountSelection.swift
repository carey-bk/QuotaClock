import Foundation

/// Provider → account choices and rendering use the same scope. Legacy selections
/// are interpreted only until the new provider parameter has been saved.
public enum WidgetAccountSelection {
    public struct Option: Equatable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) { self.id = id; self.title = title }
    }
    public static func providers(in snapshot: QuotaSnapshot?) -> [Option] {
        var options = [Option(id: WidgetDisplaySelection.heroID, title: "Hero")]
        for source in snapshot?.forSurface(.widget).providers ?? [] where !options.contains(where: { $0.id == source.baseProviderID }) {
            options.append(Option(id: source.baseProviderID, title: source.displayName))
        }
        return options
    }
    public static func accounts(in snapshot: QuotaSnapshot?, providerID: String?) -> [ProviderQuota] {
        guard let providerID, providerID != WidgetDisplaySelection.heroID else { return [] }
        return snapshot?.forSurface(.widget).providers.filter { $0.baseProviderID == providerID } ?? []
    }
    public static func migratedProviderID(in snapshot: QuotaSnapshot?, sourceID: String?, metric: [String]?, legacyProviderID: String?) -> String {
        guard let source = sourceID ?? metric.flatMap({ $0.count == 3 ? $0[0] : nil }) ?? legacyProviderID else { return WidgetDisplaySelection.heroID }
        if source == WidgetDisplaySelection.heroID { return source }
        if let value = snapshot?.providers.first(where: { $0.id == source }) { return value.baseProviderID }
        if source.hasPrefix("codex.account.") { return "codex" }
        return source
    }
    public static func defaultAccount(in snapshot: QuotaSnapshot?, providerID: String?, legacySourceID: String?, legacyMetric: [String]?) -> ProviderQuota? {
        let choices = accounts(in: snapshot, providerID: providerID)
        let oldID = legacySourceID ?? legacyMetric.flatMap { $0.count == 3 ? $0[0] : nil }
        if let oldID, let old = choices.first(where: { $0.id == oldID }) { return old }
        // A removed legacy Codex account must not silently migrate to a sibling account.
        if providerID == "codex", oldID?.hasPrefix("codex.account.") == true { return nil }
        return choices.first { $0.account?.isCurrent == true } ?? choices.first
    }
    public static func provider(in snapshot: QuotaSnapshot, providerID: String?, accountID: String?,
                                legacySourceID: String?, legacyMetric: [String]?, legacyProviderID: String?) -> ProviderQuota? {
        guard let providerID else {
            return WidgetDisplaySelection.provider(in: snapshot, sourceID: legacySourceID, metric: legacyMetric, legacyProviderID: legacyProviderID)
        }
        if providerID == WidgetDisplaySelection.heroID {
            return WidgetDisplaySelection.provider(in: snapshot, sourceID: providerID, metric: nil)
        }
        let choices = accounts(in: snapshot, providerID: providerID)
        if let accountID {
            if let selected = choices.first(where: { $0.id == accountID }) { return selected }
            // The configuration host may retain a stale dependent parameter for one render.
            // Only a sole account in the newly selected provider may be used in that case.
            let previousProvider = migratedProviderID(in: snapshot, sourceID: accountID, metric: nil, legacyProviderID: nil)
            if previousProvider != providerID, choices.count == 1 { return choices[0] }
        } else if let initial = defaultAccount(in: snapshot, providerID: providerID, legacySourceID: legacySourceID, legacyMetric: legacyMetric) {
            return initial
        }
        var missing = ProviderQuota(id: providerID, displayName: choices.first?.displayName ?? ProviderCatalog.name(providerID), planName: nil, limits: [], lastUpdated: snapshot.generatedAt)
        missing.health = ProviderHealth(state: .unavailable, reason: "Selected account unavailable")
        return missing
    }
}

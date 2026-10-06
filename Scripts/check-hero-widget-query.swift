import Foundation
import QuotaCore

/// Read-only runtime check, compiled alongside the actual Widget AppEntity/query declarations.
@main struct CheckHeroWidgetQuery {
    static func main() async throws {
        let choices = try await WidgetSourceQuery().suggestedEntities()
        precondition(choices.first?.id == WidgetDisplaySelection.heroID)
        precondition(choices.first?.title == "Hero")
        let resolved = try await WidgetSourceQuery().entities(for: [WidgetDisplaySelection.heroID, "missing-source"])
        precondition(resolved[0].title == "Hero")
        precondition(resolved[1].title == "Unavailable account")
        let snapshot = try SnapshotStore(url: SnapshotLocations.shared()).read()
        let hero = WidgetDisplaySelection.provider(in: snapshot, sourceID: choices[0].id, metric: nil)
        precondition(hero?.id == snapshot.hero?.id)
        print("PASS: actual Widget source query lists Hero first and resolves it by stable ID")
        print("PASS: unknown explicit selection remains unavailable")
        print("PASS: Hero selection matches the live published Hero; source count: \(choices.count)")
        let families = try await WidgetFamilyQuery().suggestedEntities()
        precondition(families.first?.id == WidgetDisplaySelection.heroID)
        precondition(Set(families.map(\.id)).count == families.count)
        for family in families {
            let accounts = WidgetAccountQuery.choices(in: snapshot, providerID: family.id)
            if family.id == WidgetDisplaySelection.heroID { precondition(accounts.isEmpty) }
            for account in accounts {
                precondition(snapshot.providers.first { $0.id == account.id }?.baseProviderID == family.id)
            }
        }
        print("PASS: actual Provider query deduplicates families and keeps Hero first")
        print("PASS: actual Account choices are scoped to each Provider, with no choices for Hero")
        print("Native Widget editor and WidgetKit scheduling are separate acceptance checks.")
    }
}

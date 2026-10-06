import Foundation
import QuotaCore

/// Exercise the presentation state used by SettingsView and the login controller.
/// All account IDs and preferences are fixtures; no browser or credentials are used.
@main struct CheckProviderConnection {
    static func main() throws {
        let hanz = "codex.account.hanz", alice = "codex.account.alice", vanilla = "codex.account.vanilla"
        let previous = [hanz, alice, "deepseek", "kimi"]
        var state = ProviderSetupState()
        state.beginAdding("codex", connected: previous)
        state.beginConnection()
        precondition(state.rows(connected: previous) == ["codex"] + previous)
        precondition(!state.canReorder(connected: previous, busy: true))

        // The store has appended the account, exactly as in the reported bug.
        // The completed draft must instead become that account at the same position.
        let loaded = previous + [vanilla]
        let ordered = state.connected(providerID: "codex", sourceID: vanilla, isNew: true, order: loaded)
        precondition(state.pendingID == nil)
        precondition(state.expandedID == vanilla && state.completedSourceID == vanilla)
        precondition(state.rows(connected: ordered) == [vanilla] + previous)
        precondition(!state.rows(connected: ordered).contains("codex"))
        precondition(!state.canReorder(connected: ordered, busy: true))
        precondition(state.canReorder(connected: ordered, busy: false))

        var preferences = PlatformPreferences()
        preferences.connectionOrder = previous
        preferences.surfaces = SurfaceConfiguration(menu: [hanz, "deepseek"], hero: "codex", secondary: [alice])
        let original = preferences
        preferences.reorderConnections(ordered, available: loaded)
        precondition(preferences.connectionOrder == ordered)
        precondition(preferences.surfaces == original.surfaces && preferences.menuOrder == original.menuOrder && preferences.saverOrder == original.saverOrder)
        let roundTrip = try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(preferences))
        precondition(roundTrip.connectionOrder == ordered)
        let moved = previous + [vanilla]
        preferences.reorderConnections(moved, available: loaded)
        precondition(preferences.connectionOrder == moved && state.canReorder(connected: moved, busy: false))

        // An existing account's re-login acknowledges success without moving it.
        state.expandedID = alice
        state.beginConnection()
        precondition(state.completedSourceID == nil)
        let renewed = state.connected(providerID: "codex", sourceID: alice, isNew: false, order: moved)
        precondition(renewed == moved && state.expandedID == alice && state.completedSourceID == alice)

        // A completion is scoped to its provider; it cannot consume another draft.
        state.beginAdding("glm", connected: moved)
        _ = state.connected(providerID: "codex", sourceID: alice, isNew: false, order: moved)
        precondition(state.pendingID == "glm" && state.expandedID == "glm")
        precondition(state.rows(connected: moved) == ["glm"] + moved)

        // A failed/cancelled attempt has no completion event. A retry succeeds,
        // and a second add has a fresh draft rather than a previous success label.
        state.beginAdding("codex", connected: moved)
        state.beginConnection()
        precondition(state.pendingID == "codex" && state.completedSourceID == nil)
        _ = state.connected(providerID: "codex", sourceID: alice, isNew: false, order: moved)
        precondition(state.pendingID == "codex" && state.expandedID == "codex")
        state.beginConnection()
        let linked = "codex.account.linked"
        let linkedOrder = state.connected(providerID: "codex", sourceID: linked, isNew: true, order: moved + [linked])
        precondition(state.rows(connected: linkedOrder) == [linked] + moved)
        precondition(state.canReorder(connected: linkedOrder, busy: false))
        state.beginAdding("codex", connected: linkedOrder)
        precondition(state.completedSourceID == nil && state.expandedID == "codex")
        state.cancelAdding("glm")
        precondition(state.pendingID == "codex")
        state.cancelAdding("codex")
        precondition(state.pendingID == nil && state.expandedID == nil)
        precondition(state.rows(connected: linkedOrder) == linkedOrder)
        precondition(state.canReorder(connected: linkedOrder, busy: false))
        // A late cancellation cannot delete or collapse a successfully saved row.
        state.beginAdding("codex", connected: moved)
        _ = state.connected(providerID: "codex", sourceID: linked, isNew: true, order: linkedOrder)
        state.cancelAdding("codex")
        precondition(state.expandedID == linked && state.completedSourceID == linked)

        // Opening a connected single-account provider does not create a draft.
        state.beginAdding("deepseek", connected: moved)
        precondition(state.pendingID == nil && state.rows(connected: moved) == moved)
        state.addedAPI("custom.api")
        precondition(state.pendingID == nil && state.expandedID == "custom.api")
        print("Provider connection checks passed: draft cancellation restores sorting, completed accounts survive cancellation, draft replacement, exact account expansion, success scope, persisted order, re-login, retry, and linked account.")
    }
}

import Foundation

/// Shared with the login controller so a browser round trip can replace the
/// draft even when the settings view has been recreated in the meantime.
struct ProviderSetupState {
    var expandedID: String?
    private(set) var pendingID: String?
    private(set) var completedSourceID: String?

    mutating func beginAdding(_ providerID: String, connected: [String]) {
        pendingID = connected.contains(providerID) ? nil : providerID
        expandedID = providerID
        completedSourceID = nil
    }

    mutating func beginConnection() { completedSourceID = nil }

    mutating func cancelAdding(_ providerID: String) {
        guard pendingID == providerID else { return }
        pendingID = nil
        if expandedID == providerID { expandedID = nil }
    }

    func rows(connected: [String]) -> [String] {
        guard let pendingID, !connected.contains(pendingID) else { return connected }
        return [pendingID] + connected
    }

    func canReorder(connected: [String], busy: Bool) -> Bool {
        !busy && rows(connected: connected) == connected
    }

    /// New accounts take the draft's first position. Renewing credentials keeps
    /// the existing order. Only the matching draft is consumed on success.
    mutating func connected(providerID: String, sourceID: String, isNew: Bool, order: [String]) -> [String] {
        if isNew && pendingID == providerID {
            pendingID = nil
            expandedID = sourceID
        }
        completedSourceID = sourceID
        return isNew ? [sourceID] + order.filter { $0 != sourceID } : order
    }

    mutating func addedAPI(_ sourceID: String) {
        pendingID = nil
        expandedID = sourceID
        completedSourceID = nil
    }
}

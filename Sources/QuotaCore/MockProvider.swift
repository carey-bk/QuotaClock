import Foundation
public struct MockProvider: ProviderAdapter {
    public let providerID: String
    public init(providerID: String) { self.providerID = providerID }
    public func fetchQuota(at date: Date) async throws -> ProviderQuota {
        guard let provider = Self.snapshot(at: date).providers.first(where: { $0.id == providerID }) else { throw SnapshotError.invalidData }
        return provider
    }
    public static func snapshot(at date: Date = Date()) -> QuotaSnapshot {
        // Fixed UTC fixture dates; deliberately not inferred from window labels.
        let weekly = Date(timeIntervalSince1970: 1790899200) // 2026-10-02 00:00 UTC
        let session = Date(timeIntervalSince1970: 1790344800) // 2026-09-25 14:00 UTC
        return QuotaSnapshot(generatedAt: date, providers: [
            ProviderQuota(id: "codex", displayName: "Codex", planName: "Pro 5x", limits: [
                LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: 85, resetAt: weekly, windowDuration: 604800, isPrimary: true)
            ], lastUpdated: date, bankResetCount: 1),
            ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: "Max 20x", limits: [
                LimitWindow(id: "session", displayName: "Session", remainingPercentage: 93, resetAt: session, windowDuration: 18000),
                LimitWindow(id: "weekly", displayName: "Weekly", remainingPercentage: 66, resetAt: weekly, windowDuration: 604800, isPrimary: true)
            ], lastUpdated: date)
        ])
    }
}

import Foundation

/// Compares successful provider observations, not predicted countdowns.
public struct CodexResetDetector: Codable, Sendable {
    public struct Event: Equatable, Sendable {
        public let accountID: String
        public let windowID: String
        public let weekly: Bool
        public let resetAt: Date
        public var identifier: String { "codex-reset.\(accountID).\(windowID).\(Int(resetAt.timeIntervalSince1970))" }
    }
    private struct Observation: Codable, Sendable {
        var updated: Date
        var limits: [LimitWindow]
    }
    private var observations: [String: Observation] = [:]
    public init() {}
    public mutating func consume(_ snapshot: QuotaSnapshot, now: Date = .now) -> [Event] {
        let providers = snapshot.providers.filter { $0.id == "codex" || $0.id.hasPrefix("codex.account.") }
        let active = Set(providers.map(\.id))
        observations = observations.filter { active.contains($0.key) }
        var events: [Event] = []
        for provider in providers {
            guard provider.health?.state == .healthy, provider.health?.usingLastKnownGood == false,
                  provider.lastUpdated <= now.addingTimeInterval(60),
                  now.timeIntervalSince(provider.lastUpdated) <= 300 else { continue }
            let previous = observations[provider.id]
            guard previous == nil || provider.lastUpdated > previous!.updated else { continue }
            for window in provider.limits {
                guard let duration = window.windowDuration,
                      duration == 5 * 3600 || duration == 7 * 86400,
                      let old = previous?.limits.first(where: { $0.id == window.id && $0.windowDuration == duration }),
                      let oldReset = old.resetAt, let nextReset = window.resetAt,
                      provider.lastUpdated >= oldReset,
                      nextReset > provider.lastUpdated,
                      nextReset.timeIntervalSince(oldReset) >= duration * 0.8 else { continue }
                events.append(Event(accountID: provider.id, windowID: window.id, weekly: duration == 7 * 86400, resetAt: oldReset))
            }
            // Services sometimes return the expired window for one more refresh.
            // Retain its last valid baseline until a new future window is confirmed.
            let valid = provider.limits.compactMap { window -> LimitWindow? in
                if let reset = window.resetAt, reset > provider.lastUpdated { return window }
                return previous?.limits.first { $0.id == window.id }
            }
            observations[provider.id] = Observation(updated: provider.lastUpdated, limits: valid)
        }
        return events
    }
}

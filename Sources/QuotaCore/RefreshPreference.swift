import Foundation

public enum RefreshPreference: String, Codable, CaseIterable, Sendable {
    case thirtySeconds, automaticOneMinute, twoMinutes, fiveMinutes
    public var interval: TimeInterval {
        switch self { case .thirtySeconds: 30; case .automaticOneMinute: 60; case .twoMinutes: 120; case .fiveMinutes: 300 }
    }
    public var title: String {
        switch self { case .thirtySeconds: "30 seconds"; case .automaticOneMinute: "Automatic (1 min)"; case .twoMinutes: "2 minutes"; case .fiveMinutes: "5 minutes" }
    }
    public func nextRefresh(after attempt: Date?, minimum: TimeInterval, retryAfter: Date?) -> Date {
        max((attempt ?? .distantPast).addingTimeInterval(max(interval, minimum)), retryAfter ?? .distantPast)
    }
}

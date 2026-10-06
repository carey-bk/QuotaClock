import Foundation
import CoreFoundation

import Security

public enum ProviderFetchError: Error, LocalizedError, Sendable {
    case authenticationRequired, unavailable, rateLimited, timeout, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "Authentication required"
        case .unavailable: return "Provider unavailable"
        case .rateLimited: return "Rate limited"
        case .timeout: return "Request timed out"
        case .invalidResponse: return "Provider response changed"
        }
    }
    public var healthState: ProviderHealthState {
        switch self {
        case .authenticationRequired: return .authenticationRequired
        case .unavailable: return .unavailable
        case .rateLimited: return .rateLimited
        case .timeout, .invalidResponse: return .error
        }
    }
}

private enum JSONField {
    static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
    static func remaining(_ used: Any?) throws -> Double {
        guard let value = number(used), (0...100).contains(value) else { throw ProviderFetchError.invalidResponse }
        return (100 - value).rounded(toPlaces: 2)
    }
    static func date(_ value: Any?) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if let seconds = number(value), seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: string) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            if let parsed = formatter.date(from: string) { return parsed }
        }
        throw ProviderFetchError.invalidResponse
    }
}
private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places)); return (self * factor).rounded() / factor
    }
}

public enum CodexQuotaParser {
    public static func parse(_ data: Data, at date: Date) throws -> ProviderQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderFetchError.invalidResponse }
        if root["error"] != nil { throw ProviderFetchError.unavailable }
        guard let result = JSONField.object(root["result"]), let primary = JSONField.object(result["rateLimits"]) else { throw ProviderFetchError.invalidResponse }
        var buckets: [(String, [String: Any])] = []
        if let byID = JSONField.object(result["rateLimitsByLimitId"]), !byID.isEmpty {
            buckets = byID.compactMap { key, value in JSONField.object(value).map { (key, $0) } }.sorted { $0.0 < $1.0 }
        } else { buckets = [(primary["limitId"] as? String ?? "codex", primary)] }
        var limits: [LimitWindow] = []
        for (bucketID, bucket) in buckets {
            let label = (bucket["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            for (slot, fallback) in [("primary", "Primary"), ("secondary", "Secondary")] {
                guard let window = JSONField.object(bucket[slot]) else { continue }
                let duration = JSONField.number(window["windowDurationMins"]).map { $0 * 60 }
                let name: String
                if let label { name = "\(label) \(fallback)" }
                else if let duration, duration == 300 * 60 { name = "5-hour" }
                else if let duration, duration == 10080 * 60 { name = "Weekly" }
                else { name = fallback }
                limits.append(LimitWindow(id: "\(bucketID).\(slot)", displayName: name,
                    remainingPercentage: try JSONField.remaining(window["usedPercent"]),
                    resetAt: try JSONField.date(window["resetsAt"]), windowDuration: duration,
                    isPrimary: bucketID == "codex" && slot == "primary"))
            }
        }
        guard !limits.isEmpty else { throw ProviderFetchError.invalidResponse }
        if !limits.contains(where: \.isPrimary) { limits[0].isPrimary = true }
        let plan = (primary["planType"] as? String).map { raw -> String in
            switch raw.lowercased().replacingOccurrences(of: "_", with: "") {
            case "prolite": return "Pro 5x"
            case "pro": return "Pro 20x"
            case "plus": return "Plus"
            case "free": return "Free"
            case "team": return "Team"
            case "business": return "Business"
            case "enterprise": return "Enterprise"
            default: return raw
            }
        }
        let resetCredits = JSONField.object(result["rateLimitResetCredits"])
        let bankResets = JSONField.number(resetCredits?["availableCount"]).map(Int.init)
        return ProviderQuota(id: "codex", displayName: "Codex", planName: plan, limits: limits, lastUpdated: date, bankResetCount: bankResets)
    }
}

/// Parses optional account/usage/read aggregates. It never reads auth files or
/// session content; malformed usage leaves quota refresh intact.
public enum CodexUsageParser {
    public static func parse(_ data: Data) throws -> UsageStatistics {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = JSONField.object(root["result"]),
              let summary = JSONField.object(result["summary"]) else { throw ProviderFetchError.invalidResponse }
        func count(_ value: Any?) -> Int64? {
            guard let number = JSONField.number(value), number >= 0,
                  number < Double(Int64.max), number.rounded() == number else { return nil }
            return Int64(number)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let days: [UsageDay] = (result["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket in
            guard let key = bucket["startDate"] as? String,
                  let date = formatter.date(from: key),
                  let tokens = count(bucket["tokens"]) else { return nil }
            return UsageDay(date: date, tokens: tokens)
        }.sorted { $0.date < $1.date }
        return UsageStatistics(totalTokens: count(summary["lifetimeTokens"]),
                               peakDailyTokens: count(summary["peakDailyTokens"]),
                               lastDailyTokens: days.last?.tokens,
                               dailyHistory: Array(days.suffix(7)))
    }
}

public enum ClaudeQuotaParser {
    public static func parse(_ data: Data, at date: Date) throws -> ProviderQuota {
        let json = try JSONSerialization.jsonObject(with: data)
        var windows: [LimitWindow] = []
        if let root = json as? [String: Any] {
            let buckets = JSONField.object(root["rate_limits"]) ?? root
            // Current Claude Code status line / OAuth usage field names. Unknown buckets are ignored.
            for (key, name) in [("five_hour", "Session"), ("seven_day", "Weekly"), ("seven_day_opus", "Opus Weekly"), ("seven_day_sonnet", "Sonnet Weekly")] {
                guard let item = JSONField.object(buckets[key]) else { continue }
                windows.append(LimitWindow(id: key, displayName: name,
                    remainingPercentage: try JSONField.remaining(item["utilization"] ?? item["used_percentage"]),
                    resetAt: try JSONField.date(item["resets_at"]), isPrimary: key == "five_hour"))
            }
        } else if let rows = json as? [[String: Any]] {
            // Newer OAuth usage responses use rows with provider-authored labels.
            for row in rows where row["percent"] != nil {
                guard let kind = row["kind"] as? String, !kind.isEmpty else { continue }
                let scope = JSONField.object(row["scope"])
                let model = JSONField.object(scope?["model"])?["display_name"] as? String
                let name: String
                switch kind {
                case "session": name = "Session"
                case "weekly_all": name = "Weekly"
                case "weekly_scoped": name = model.map { "\($0) Weekly" } ?? "Scoped Weekly"
                default: name = kind
                }
                windows.append(LimitWindow(id: kind + (model.map { ".\($0)" } ?? ""), displayName: name,
                    remainingPercentage: try JSONField.remaining(row["percent"]),
                    resetAt: try JSONField.date(row["resets_at"]), isPrimary: kind == "session"))
            }
        }
        guard !windows.isEmpty else { throw ProviderFetchError.invalidResponse }
        if !windows.contains(where: \.isPrimary) { windows[0].isPrimary = true }
        return ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: nil, limits: windows, lastUpdated: date)
    }
}

public struct CodexProviderAdapter: ProviderAdapter {
    public let providerID = "codex"
    public init() {}
    public func fetchQuota(at date: Date) async throws -> ProviderQuota {
        let data = try await CodexAppServerTransport().readAccountData()
        var quota = try CodexQuotaParser.parse(data.rateLimits, at: date)
        if let usage = data.usage { quota.usage = try? CodexUsageParser.parse(usage) }
        return quota
    }
}

public struct ClaudeProviderAdapter: ProviderAdapter {
    public let providerID = "claude-code"
    private let credential: @Sendable () -> String?
    private let client: any ProviderHTTPClient
    public init(credential: @escaping @Sendable () -> String? = { ClaudeCredentialSource.accessToken() }, client: any ProviderHTTPClient = LiveProviderHTTPClient()) {
        self.credential = credential; self.client = client
    }
    public func fetchQuota(at date: Date) async throws -> ProviderQuota {
        guard let token = credential() else { throw ProviderFetchError.authenticationRequired }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderFetchError.unavailable }
        switch http.statusCode {
        case 200: return try ClaudeQuotaParser.parse(data, at: date)
        case 401, 403: throw ProviderFetchError.authenticationRequired
        case 429: throw ProviderFetchError.rateLimited
        default: throw ProviderFetchError.unavailable
        }
    }
}

public enum ClaudeCredentialSource {
    public static func accessToken() -> String? {
        // Read Claude Code's own active credential. Never copy it to QuotaClock storage.
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: path),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = root["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty { return token }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return oauth["accessToken"] as? String
    }
}

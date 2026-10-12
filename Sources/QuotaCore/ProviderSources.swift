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
        guard data.count <= 1_048_576 else { throw ProviderFetchError.invalidResponse }
        let json = try JSONSerialization.jsonObject(with: data)
        let root = json as? [String: Any]
        if root?["error"] != nil { throw ProviderFetchError.invalidResponse }
        let buckets = JSONField.object(root?["rate_limits"]) ?? root ?? [:]
        let rows = buckets["limits"] as? [[String: Any]] ?? json as? [[String: Any]] ?? []
        if let value = buckets["limits"], !(value is NSNull), !(value is [[String: Any]]) {
            throw ProviderFetchError.invalidResponse
        }
        var windows: [LimitWindow] = []
        // Named windows remain authoritative for session/all-model usage; scoped rows supplement them.
        for (key, name) in [("five_hour", "Session"), ("seven_day", "Weekly"),
                             ("seven_day_opus", "Opus Weekly"), ("seven_day_sonnet", "Sonnet Weekly")] {
            guard let item = JSONField.object(buckets[key]) else { continue }
            windows.append(LimitWindow(id: key, displayName: name,
                remainingPercentage: try JSONField.remaining(item["utilization"] ?? item["used_percentage"]),
                resetAt: try JSONField.date(item["resets_at"]),
                windowDuration: key == "five_hour" ? 18_000 : 604_800, isPrimary: key == "five_hour"))
        }
        var seenRows = Set<String>()
        for row in rows {
            guard let kind = row["kind"] as? String,
                  ["session", "weekly_all", "weekly_scoped"].contains(kind) else { continue }
            // is_active is not an enforcement flag: upstream observed enforceable rows with false.
            let model = JSONField.object(JSONField.object(row["scope"])?["model"])
            let label = (model?["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = (model?["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id: String
            let name: String
            switch kind {
            case "session": id = "five_hour"; name = "Session"
            case "weekly_all": id = "seven_day"; name = "Weekly"
            default:
                guard let identity = [modelID, label].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
                    throw ProviderFetchError.invalidResponse
                }
                id = "weekly_scoped." + identity
                name = (label.flatMap { $0.isEmpty ? nil : $0 } ?? identity) + " Weekly"
            }
            guard seenRows.insert(id).inserted else { throw ProviderFetchError.invalidResponse }
            if windows.contains(where: { $0.id == id }) { continue }
            // Only replace the matching model's legacy bucket, never unrelated model quotas.
            if kind == "weekly_scoped" {
                let modelKey = (modelID ?? label ?? "").lowercased()
                if ["opus", "sonnet"].contains(modelKey) { windows.removeAll { $0.id == "seven_day_" + modelKey } }
            }
            windows.append(LimitWindow(id: id, displayName: name,
                remainingPercentage: try JSONField.remaining(row["percent"]),
                resetAt: try JSONField.date(row["resets_at"]),
                windowDuration: kind == "session" ? 18_000 : 604_800, isPrimary: kind == "session"))
        }
        func rank(_ window: LimitWindow) -> Int { window.id == "five_hour" ? 0 : window.id == "seven_day" ? 1 : 2 }
        windows.sort { rank($0) == rank($1) ? $0.id < $1.id : rank($0) < rank($1) }

        guard !windows.isEmpty else { throw ProviderFetchError.invalidResponse }
        if !windows.contains(where: \.isPrimary) { windows[0].isPrimary = true }
        var quota = ProviderQuota(id: "claude-code", displayName: "Claude", planName: nil, limits: windows, lastUpdated: date)
        if let extra = JSONField.object(buckets["extra_usage"]), let flag = extra["is_enabled"] as? NSNumber,
           CFGetTypeID(flag) == CFBooleanGetTypeID() {
            if !flag.boolValue { quota.claudeExtraUsage = .init(enabled: false) }
            else {
                let places = JSONField.number(extra["decimal_places"]) ?? 2
                if (0...6).contains(places), places.rounded() == places {
                    let scale = pow(10, places)
                    func money(_ key: String) -> Double? {
                        guard let value = JSONField.number(extra[key]), value >= 0 else { return nil }
                        return value / scale
                    }
                    let currency = (extra["currency"] as? String ?? "USD").uppercased()
                    if currency.count == 3, currency.allSatisfy({ $0.isASCII && $0.isLetter }) {
                        quota.claudeExtraUsage = .init(enabled: true, used: money("used_credits"), limit: money("monthly_limit"), currency: currency)
                    }
                }
            }
        }
        quota.bankResetCount = resetCount(buckets["cedar_ember"] ?? root?["cedar_ember"], at: date)
        return quota
    }
    // Optional inventory must never make otherwise valid usage unavailable or invent a zero.
    private static func resetCount(_ value: Any?, at date: Date) -> Int? {
        guard let status = JSONField.object(value),
              (status["eligible"] as? Bool) != false,
              let grants = status["grants"] as? [[String: Any]] else { return nil }
        var total = 0
        var seen = Set<String>()
        for grant in grants {
            guard let number = JSONField.number(grant["resets_left"]), number >= 0,
                  let count = Int(exactly: number) else { return nil }
            if let id = grant["id"] as? String, !seen.insert(id).inserted { return nil }
            // An unreadable date makes this inventory unknown, not an available grant.
            let start: Date?
            let end: Date?
            do {
                start = try JSONField.date(grant["starts_at"])
                end = try JSONField.date(grant["ends_at"])
            } catch { return nil }
            if let start, start > date { continue }
            if let end, end <= date { continue }
            if (grant["paused"] as? Bool) == true { continue }
            let sum = total.addingReportingOverflow(count)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
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
    private let credential: @Sendable () -> (token: String, plan: String?)?
    private let client: any ProviderHTTPClient
    private var localUsageEnabled = false
    public init(credential: @escaping @Sendable () -> String?, client: any ProviderHTTPClient = ClaudeHTTPClient()) {
        self.credential = { credential().map { ($0, nil) } }; self.client = client
    }
    public init(client: any ProviderHTTPClient = ClaudeHTTPClient()) {
        self.localUsageEnabled = true
        self.credential = {
            if UserDefaults.standard.string(forKey: "claude.loginSource") == "desktop" {
                return ClaudeDesktopCredentials.account()
            }
            return ClaudeCredentialSource.account()
        }; self.client = client
    }
    public func fetchQuota(at date: Date) async throws -> ProviderQuota {
        let loginSource = UserDefaults.standard.string(forKey: "claude.loginSource") ?? "code"
        guard let account = credential() else { throw ProviderFetchError.authenticationRequired }
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ProviderFetchError.authenticationRequired }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15
        do {
            var (data, response) = try await client.data(for: request)
            // Older accounts/surfaces can reject the optional inventory query.
            if let status = (response as? HTTPURLResponse)?.statusCode, status == 400 || status == 403 {
                request.url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
                (data, response) = try await client.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else { throw ProviderFetchError.unavailable }
            switch http.statusCode {
            case 200:
                var quota = try ClaudeQuotaParser.parse(data, at: date)
                quota.planName = account.plan
                if localUsageEnabled {
                    let scope: LocalTokenScope = loginSource == "desktop" ? .claudeDesktop : .claudeCLI
                    quota.usage = await ClaudeLocalUsage.shared.statistics(scope: scope, at: date)
                    guard (UserDefaults.standard.string(forKey: "claude.loginSource") ?? "code") == loginSource else { throw CancellationError() }
                }
                return quota
            case 401: throw ProviderFetchError.authenticationRequired
            case 429: throw ProviderFetchError.rateLimited
            default: throw ProviderFetchError.unavailable
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? ProviderFetchError.timeout : ProviderFetchError.unavailable
        }
    }
}

/// Quota credentials never follow redirects or enter the shared HTTP cache/cookie jar.
public struct ClaudeHTTPClient: ProviderHTTPClient {
    public init() {}
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: .ephemeral, delegate: ClaudeRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }
}
private final class ClaudeRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ClaudeCredentialSource {
    /// A pure decoder for tests. Expiration uses Claude Code's millisecond timestamp.
    static func accessToken(in data: Data, at date: Date = .now) -> String? {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let raw = oauth["accessToken"] as? String else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        if let expiry = oauth["expiresAt"] {
            guard let milliseconds = JSONField.number(expiry), milliseconds / 1000 > date.timeIntervalSince1970 else { return nil }
        }
        return token
    }
    static func plan(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let type = oauth["subscriptionType"] as? String else { return nil }
        switch type.lowercased() {
        case "pro": return "Pro"
        case "max":
            let tier = oauth["rateLimitTier"] as? String ?? ""
            if tier == "default_claude_max_5x" { return "Max 5x" }
            if tier == "default_claude_max_20x" { return "Max 20x" }
            return "Max"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return nil
        }
    }
    public static func accessToken() -> String? { account()?.token }
    static func account() -> (token: String, plan: String?)? {
        func decode(_ data: Data) -> (token: String, plan: String?)? {
            accessToken(in: data).map { ($0, plan(in: data)) }
        }
        // Read only: Claude Code owns refresh and credential storage. On macOS its Keychain is authoritative.
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return decode(data) }
        // Do not bypass a denied Keychain read with a possibly unrelated file account.
        guard status == errSecItemNotFound else { return nil }
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return decode(data)
    }
}

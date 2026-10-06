import Foundation
import CoreFoundation

/// Schema helpers deliberately reject booleans, missing numbers and non-finite values.
enum MeterJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_048_576, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else { throw ProviderFetchError.invalidResponse }
        return root
    }
    static func number(_ value: Any?) throws -> Decimal {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { return n.decimalValue }
        if let s = value as? String, s.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
           let n = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")), !n.isNaN { return n }
        throw ProviderFetchError.invalidResponse
    }
    static func date(_ value: Any?, milliseconds: Bool = false) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue > 0 {
            return Date(timeIntervalSince1970: n.doubleValue / (milliseconds ? 1000 : 1))
        }
        if let s = value as? String {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
        }
        throw ProviderFetchError.invalidResponse
    }
    static func percent(used: Decimal, total: Decimal) throws -> Decimal {
        guard total > 0, used >= 0, used <= total else { throw ProviderFetchError.invalidResponse }
        return (total - used) / total * 100
    }
}
struct ProductHTTPTransport: Sendable {
    var client: any ProviderHTTPClient
    func get(_ url: String, key: String?, bearer: Bool = true) async throws -> Data {
        guard let key, !key.isEmpty else { throw ProviderFetchError.authenticationRequired }
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 15
        request.setValue(bearer ? "Bearer \(key)" : key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderFetchError.unavailable }
            switch http.statusCode {
            case 200: guard data.count <= 1_048_576 else { throw ProviderFetchError.invalidResponse }; return data
            case 401, 403: throw ProviderFetchError.authenticationRequired
            case 429: throw ProviderFetchError.rateLimited
            default: throw ProviderFetchError.unavailable
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? ProviderFetchError.timeout : ProviderFetchError.unavailable
        }
    }
}
public struct GLMProvider: ProductAdapter {
    public let descriptor = ProviderCatalog.product("glm.coding-plan")
    private let credential: @Sendable () -> String?
    private let client: any ProviderHTTPClient
    public init(credential: @escaping @Sendable () -> String? = { ProductKeychain(.init(providerID: "glm", productID: "glm.coding-plan")).read() }, client: any ProviderHTTPClient = LiveProviderHTTPClient()) {
        self.credential = credential; self.client = client
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        try Self.parse(await ProductHTTPTransport(client: client).get("https://open.bigmodel.cn/api/monitor/usage/quota/limit", key: credential(), bearer: false), at: date)
    }
    public static func parse(_ data: Data, at date: Date) throws -> ProductQuota {
        let root = try MeterJSON.object(data)
        if let success = root["success"] as? Bool, !success { throw ProviderFetchError.unavailable }
        let payload = root["data"] as? [String: Any] ?? root
        guard let limits = payload["limits"] as? [[String: Any]] else { throw ProviderFetchError.invalidResponse }
        let meters = try limits.compactMap { row -> Meter? in
            guard let type = row["type"] as? String, ["TOKENS_LIMIT", "TIME_LIMIT"].contains(type) else { return nil }
            let used = try MeterJSON.number(row["percentage"])
            let remaining = try MeterJSON.percent(used: used, total: 100)
            // Official helper identifies these two types; no unverified weekly/reset/plan fields.
            return Meter(id: type, displayName: type == "TOKENS_LIMIT" ? "Token usage (5 Hour)" : "MCP usage (1 Month)",
                kind: .percentageQuota, value: remaining, updatedAt: date, reliability: .providerSupportedUndocumented)
        }
        guard !meters.isEmpty else { throw ProviderFetchError.invalidResponse }
        return try ProductQuota(id: "glm.coding-plan", providerID: "glm", displayName: "GLM Coding Plan", meters: meters,
                            at: date, defaultMeterID: "TOKENS_LIMIT").validated()
    }
}
public struct KimiProvider: ProductAdapter {
    public let descriptor = ProviderCatalog.product("kimi.code")
    private let credential: @Sendable () -> String?
    private let client: any ProviderHTTPClient
    public init(credential: @escaping @Sendable () -> String? = { ProductKeychain(.init(providerID: "kimi", productID: "kimi.code")).read() }, client: any ProviderHTTPClient = LiveProviderHTTPClient()) {
        self.credential = credential; self.client = client
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        try Self.parse(await ProductHTTPTransport(client: client).get("https://api.kimi.com/coding/v1/usages", key: credential()), at: date)
    }
    public static func parse(_ data: Data, at date: Date) throws -> ProductQuota {
        let root = try MeterJSON.object(data)
        var meters: [Meter] = []
        func add(_ row: [String: Any], id: String, label: String, duration: TimeInterval? = nil) throws {
            let total = try MeterJSON.number(row["limit"])
            let used: Decimal
            if row["used"] != nil { used = try MeterJSON.number(row["used"]) }
            else { used = total - (try MeterJSON.number(row["remaining"])) }
            let value = try MeterJSON.percent(used: used, total: total)
            if let remaining = row["remaining"], try MeterJSON.number(remaining) != total - used { throw ProviderFetchError.invalidResponse }
            let name = row["name"] as? String ?? row["title"] as? String ?? label
            let reset = try MeterJSON.date(row["reset_at"] ?? row["resetAt"] ?? row["reset_time"] ?? row["resetTime"])
            meters.append(Meter(id: id, displayName: name, kind: .percentageQuota, value: value, total: total,
                remaining: total - used, resetAt: reset, windowDuration: duration, updatedAt: date, reliability: .providerSupportedUndocumented))
        }
        if let usage = root["usage"] as? [String: Any] { try add(usage, id: "current-plan", label: "Current plan quota") }
        if let rows = root["limits"] {
            guard let rows = rows as? [[String: Any]] else { throw ProviderFetchError.invalidResponse }
            for item in rows {
                let detail = item["detail"] as? [String: Any] ?? item
                let window = item["window"] as? [String: Any] ?? [:]
                let name = item["name"] as? String ?? item["title"] as? String ?? item["scope"] as? String
                let duration = try (window["duration"] ?? item["duration"] ?? detail["duration"]).map { try MeterJSON.number($0) }
                let unit = window["timeUnit"] as? String ?? item["timeUnit"] as? String ?? detail["timeUnit"] as? String
                let scale: Double? = ["MINUTE": 60, "HOUR": 3600, "DAY": 86400, "SECOND": 1][unit ?? ""]
                let seconds = duration.flatMap { d in scale.map { NSDecimalNumber(decimal: d).doubleValue * $0 } }
                let windowID = duration.map { "window.\($0).\(unit ?? "unknown")" }
                guard let id = windowID ?? name.map({ "scope.\($0)" }) else { throw ProviderFetchError.invalidResponse }
                let label = name ?? duration.map { "\($0) \(unit ?? "") quota" } ?? "Quota"
                try add(detail, id: id, label: label, duration: seconds)
            }
        }
        guard !meters.isEmpty else { throw ProviderFetchError.invalidResponse }
        return try ProductQuota(id: "kimi.code", providerID: "kimi", displayName: "Kimi Code", meters: meters,
                            at: date, defaultMeterID: "current-plan").validated()
    }
}
public struct KimiAPIProvider: ProductAdapter {
    public let descriptor: ProductDescriptor
    private let international: Bool
    private let credential: @Sendable () -> String?
    private let client: any ProviderHTTPClient
    public init(international: Bool = false, credential: (@Sendable () -> String?)? = nil, client: any ProviderHTTPClient = LiveProviderHTTPClient()) {
        self.international = international
        let id = international ? "kimi.api-international" : "kimi.api"
        descriptor = ProviderCatalog.product(id)
        self.credential = credential ?? { ProductKeychain(.init(providerID: "kimi", productID: id)).read() }; self.client = client
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        try Self.parse(await ProductHTTPTransport(client: client).get(international ? "https://api.moonshot.ai/v1/users/me/balance" : "https://api.moonshot.cn/v1/users/me/balance", key: credential()), at: date, international: international)
    }
    public static func parse(_ data: Data, at date: Date, international: Bool = false) throws -> ProductQuota {
        let root = try MeterJSON.object(data)
        guard try MeterJSON.number(root["code"]) == 0, root["status"] as? Bool == true,
              let payload = root["data"] as? [String: Any] else { throw ProviderFetchError.invalidResponse }
        let value = try MeterJSON.number(payload["available_balance"])
        // Separate product IDs prevent keys and currency from crossing regional accounts.
        let currency = international ? "USD" : "CNY"
        let id = international ? "kimi.api-international" : "kimi.api"
        let meter = Meter(id: "balance.\(currency)", displayName: "API Balance", kind: .balance, value: value,
                          currency: currency, updatedAt: date, reliability: .officialPublicAPI)
        return try ProductQuota(id: id, providerID: "kimi", displayName: ProviderCatalog.product(id).displayName,
                                meters: [meter], at: date).validated()
    }
}

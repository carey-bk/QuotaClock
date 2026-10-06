import Foundation
import Security

public struct DeepSeekKeychain: Sendable {
    public init() {}
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.quotaclock.deepseek.api-key",
         kSecAttrAccount as String: "default"]
    }
    public func read() -> String? {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { return nil }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }
    public func save(_ key: String) throws {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { throw ProviderFetchError.unavailable }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderFetchError.authenticationRequired }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ProviderFetchError.unavailable }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ProviderFetchError.unavailable }
    }
    public func delete() throws {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { throw ProviderFetchError.unavailable }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProviderFetchError.unavailable }
    }
}

public enum DeepSeekBalanceParser {
    private static func amount(_ value: Any?) throws -> Decimal {
        guard let text = value as? String, text.range(of: #"^(0|[1-9][0-9]*)(\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { throw ProviderFetchError.invalidResponse }
        return amount
    }
    public static func parse(_ data: Data, at date: Date) throws -> ProviderQuota {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let available = root["is_available"] as? Bool,
              let rows = root["balance_infos"] as? [[String: Any]], !rows.isEmpty else { throw ProviderFetchError.invalidResponse }
        let balances = try rows.map { row -> BalanceAmount in
            guard let currency = row["currency"] as? String, ["CNY", "USD"].contains(currency) else { throw ProviderFetchError.invalidResponse }
            return BalanceAmount(currency: currency, total: try amount(row["total_balance"]),
                granted: try amount(row["granted_balance"]), toppedUp: try amount(row["topped_up_balance"]))
        }
        return ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [],
            lastUpdated: date, balances: balances, balanceAvailable: available)
    }
}

public protocol ProviderHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
public struct LiveProviderHTTPClient: ProviderHTTPClient {
    public init() {}
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}
public struct DeepSeekProviderAdapter: ProviderAdapter {
    public let providerID = "deepseek"
    private let credential: @Sendable () -> String?
    private let client: any ProviderHTTPClient
    public init(credential: @escaping @Sendable () -> String? = { DeepSeekKeychain().read() }, client: any ProviderHTTPClient = LiveProviderHTTPClient()) {
        self.credential = credential; self.client = client
    }
    public func fetchQuota(at date: Date) async throws -> ProviderQuota {
        guard let key = credential(), !key.isEmpty else { throw ProviderFetchError.authenticationRequired }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderFetchError.unavailable }
            switch http.statusCode {
            case 200: return try DeepSeekBalanceParser.parse(data, at: date)
            case 401, 403: throw ProviderFetchError.authenticationRequired
            case 429: throw ProviderFetchError.rateLimited
            default: throw ProviderFetchError.unavailable
            }
        } catch let error as URLError {
            throw error.code == .timedOut ? ProviderFetchError.timeout : ProviderFetchError.unavailable
        }
    }
}

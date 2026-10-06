import Foundation
import CryptoKit

/// Public presentation only. Server identity, email and credentials stay in the private registry/vault.
public struct AccountPresentation: Codable, Equatable, Sendable {
    public var id: UUID
    public var signature: String
    public var isCurrent: Bool
    public init(id: UUID, signature: String, isCurrent: Bool = false) {
        self.id = id; self.signature = signature; self.isCurrent = isCurrent
    }
}
public enum AccountConnection: String, Codable, Sendable { case currentSession, independent }
public struct ProviderAccount: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public let providerID: String
    public var signature: String
    public let identityKey: String
    public var email: String?
    public var plan: String?
    public var connection: AccountConnection
    /// When true, only Codex may refresh this credential lineage. QuotaClock
    /// reads the live access token until an explicit switch hands ownership back.
    public var credentialsHandedToCodex: Bool?
    public init(id: UUID = UUID(), providerID: String = "codex", signature: String, identityKey: String,
                email: String? = nil, plan: String? = nil, connection: AccountConnection) {
        self.id = id; self.providerID = providerID; self.signature = signature; self.identityKey = identityKey
        self.email = email; self.plan = plan; self.connection = connection
    }
    public static func validSignature(_ value: String) -> Bool {
        (1...12).contains(value.utf8.count) && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) }
    }
    public var sourceID: String { DisplaySourceID.make(provider: providerID, account: id) }
    public var productID: String { "\(providerID).subscription.account.\(id.uuidString.lowercased())" }
    public var title: String { "\(ProviderCatalog.name(providerID)) \(signature)" }
    public func presentation(currentIdentity: String?) -> AccountPresentation {
        AccountPresentation(id: id, signature: signature, isCurrent: identityKey == currentIdentity)
    }
    public func switchOption(currentIdentity: String?) -> CodexAccountSwitchOption {
        .init(id: id, name: signature, isCurrent: identityKey == currentIdentity,
              canSwitch: providerID == "codex" && identityKey != currentIdentity &&
                connection == .independent && credentialsHandedToCodex != true)
    }
    public var descriptor: ProductDescriptor {
        ProductDescriptor(id: productID, providerID: providerID, displayName: "Codex Subscription",
                          reliability: .officialCLI, connection: "account")
    }
}
/// The menu receives only display names and eligibility, never credentials or email.
public struct CodexAccountSwitchOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let isCurrent: Bool
    public let canSwitch: Bool
    public init(id: UUID, name: String, isCurrent: Bool, canSwitch: Bool) {
        self.id = id; self.name = name; self.isCurrent = isCurrent; self.canSwitch = canSwitch
    }
}
public enum DisplaySourceID {
    public static func make(provider: String, account: UUID?) -> String {
        account.map { "\(provider).account.\($0.uuidString.lowercased())" } ?? provider
    }
}
public extension ProviderQuota {
    var baseProviderID: String { products?.first?.providerID ?? id }
    var nickname: String? { account?.signature ?? displayPreference?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyNickname }
    var sourceTitle: String { displayName + (nickname.map { " \($0)" } ?? "") }
}
public extension QuotaSnapshot {
    /// Explicit selections never fall through to another account when removed or hidden.
    func displaySource(id: String, surface: DisplaySurface) -> ProviderQuota? {
        forSurface(surface).providers.first { $0.id == id }
    }
}
public extension ProductQuota {
    var sourceID: String { DisplaySourceID.make(provider: providerID, account: account?.id) }
}

public enum AccountError: Error, LocalizedError, Sendable {
    case invalidSignature, duplicate, identityChanged, currentLoginUnavailable, busy, storage, recoveryRequired, invalidLoginURL
    public var errorDescription: String? {
        switch self {
        case .invalidSignature: "Use 1–12 English letters for the signature."
        case .duplicate: "This account or signature is already saved."
        case .identityChanged: "Account identity changed. Reconnect this account."
        case .currentLoginUnavailable: "This linked account is not the current Codex login. Sign in separately to monitor it."
        case .busy: "This account is busy. Try again shortly."
        case .storage: "Could not access secure account storage."
        case .recoveryRequired: "Credential recovery is pending. Unlock Keychain and refresh before reconnecting."
        case .invalidLoginURL: "Codex returned an unsupported sign-in URL."
        }
    }
}

/// Decode only the fields required for identity and the official app-server interface.
/// Token claims are used for local identity matching, never as proof of successful authentication.
struct CodexCredential: Sendable {
    let data: Data
    let accessToken: String
    let refreshToken: String?
    let accountID: String
    let identityKey: String
    let email: String?
    let plan: String?
    init(_ data: Data) throws {
        guard data.count <= 131_072,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["auth_mode"] as? String == nil || object["auth_mode"] as? String == "chatgpt",
              let tokens = object["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else { throw ProviderFetchError.authenticationRequired }
        let claims = Self.claims(tokens["id_token"] as? String) ?? Self.claims(access) ?? [:]
        let auth = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        guard let account = (tokens["account_id"] as? String) ?? (auth["chatgpt_account_id"] as? String), !account.isEmpty,
              let subject = (auth["chatgpt_user_id"] as? String) ?? (claims["sub"] as? String), !subject.isEmpty else {
            throw ProviderFetchError.authenticationRequired
        }
        self.data = data; accessToken = access; refreshToken = tokens["refresh_token"] as? String
        accountID = account
        let identity = "\(account.utf8.count):\(account)\(subject.utf8.count):\(subject)"
        identityKey = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        email = claims["email"] as? String ?? (claims["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String
        plan = auth["chatgpt_plan_type"] as? String
    }
    private static func claims(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    var externalLogin: [String: Any] {
        var fields: [String: Any] = ["type": "chatgptAuthTokens", "accessToken": accessToken, "chatgptAccountId": accountID]
        if let plan { fields["chatgptPlanType"] = plan }
        return fields
    }
}

public struct CodexActiveLogin: Sendable {
    public let home: URL
    public init(home: URL? = nil) {
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    // Intentionally read-only. No fallback launches Codex against the active home.
    func credential() throws -> CodexCredential {
        // A leftover file is not evidence of the active login when Codex uses another store.
        if let config = try? String(contentsOf: home.appendingPathComponent("config.toml")),
           let pattern = try? NSRegularExpression(pattern: #"(?m)^\s*cli_auth_credentials_store\s*=\s*["']([^"']+)["']"#),
           let match = pattern.firstMatch(in: config, range: NSRange(config.startIndex..., in: config)),
           let range = Range(match.range(at: 1), in: config), config[range] != "file" {
            throw AccountError.currentLoginUnavailable
        }
        let url = home.appendingPathComponent("auth.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 131_072,
              let data = try? Data(contentsOf: url) else { throw AccountError.currentLoginUnavailable }
        return try CodexCredential(data)
    }
    public func identityKey() -> String? { try? credential().identityKey }
}

private extension String { var nonEmptyNickname: String? { isEmpty ? nil : self } }

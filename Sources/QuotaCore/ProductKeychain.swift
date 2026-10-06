import Foundation
import Security

public struct CredentialIdentity: Equatable, Sendable {
    public let providerID: String
    public let productID: String
    public let profileID: String
    public init(providerID: String, productID: String, profileID: String = "default") {
        self.providerID = providerID; self.productID = productID; self.profileID = profileID
    }
    public var account: String {
        // Length-prefix encoding prevents delimiter collisions.
        [providerID, productID, profileID].map { "\($0.utf8.count):\($0)" }.joined()
    }
}
public struct ProductKeychain: Sendable {
    public let identity: CredentialIdentity
    public init(_ identity: CredentialIdentity) { self.identity = identity }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.quotaclock.products.v2",
         kSecAttrAccount as String: identity.account]
    }
    private var legacyDeepSeek: Bool { identity == CredentialIdentity(providerID: "deepseek", productID: "deepseek.api") }
    public func read() -> String? {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { return nil }
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        // Non-destructive legacy mapping preserves rollback and existing Keychain authorization.
        return legacyDeepSeek ? DeepSeekKeychain().read() : nil
    }
    public func save(_ key: String) throws {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { throw ProviderFetchError.unavailable }
        // Existing DeepSeek identity is an intentional v2 mapping, not a copied plaintext secret.
        if legacyDeepSeek { try DeepSeekKeychain().save(key); return }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ProviderFetchError.authenticationRequired }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ProviderFetchError.unavailable }
        var q = query; q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw ProviderFetchError.unavailable }
    }
    public func delete() throws {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { throw ProviderFetchError.unavailable }
        if legacyDeepSeek { try DeepSeekKeychain().delete() }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProviderFetchError.unavailable }
    }
}

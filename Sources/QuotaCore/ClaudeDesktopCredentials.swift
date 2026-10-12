import Foundation
import Security
import CommonCrypto

/// Read-only Desktop OAuth support. Never refresh or rewrite another app's credentials.
public enum ClaudeDesktopCredentials {
    static func decrypt(_ encrypted: Data, password: Data) -> Data? {
        guard encrypted.count > 3, encrypted.count <= 1_048_576,
              encrypted.prefix(3) == Data("v10".utf8), !password.isEmpty else { return nil }
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: 16)
        let derived = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.baseAddress!.assumingMemoryBound(to: CChar.self), password.count,
                                salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, 16)
        }
        guard derived == kCCSuccess else { return nil }
        let input = Array(encrypted.dropFirst(3)), iv = [UInt8](repeating: 32, count: 16)
        var output = [UInt8](repeating: 0, count: input.count + 16), count = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, 16, iv, input, input.count, &output, output.count, &count)
        guard status == kCCSuccess else { return nil }
        let clear = Data(output.prefix(count))
        // CBC padding alone cannot authenticate a key; require the expected JSON shape.
        guard (try? JSONSerialization.jsonObject(with: clear)) is [String: Any] else { return nil }
        return clear
    }

    static func decode(in cache: Data, accountID: String, at date: Date = .now) -> (token: String, plan: String?)? {
        guard cache.count <= 1_048_576, UUID(uuidString: accountID) != nil,
              let entries = try? JSONSerialization.jsonObject(with: cache) as? [String: Any] else { return nil }
        let accounts = entries.compactMap { key, value -> (token: String, plan: String?)? in
            // Match only the active Desktop identity, official host and usage scope.
            guard key.hasPrefix("acct:\(accountID)|"),
                  key.contains(":https://api.anthropic.com:"),
                  let scope = key.components(separatedBy: ":https://api.anthropic.com:").last,
                  scope == "user:profile",
                  let entry = value as? [String: Any], let raw = entry["token"] as? String,
                  let expiry = entry["expiresAt"] as? NSNumber, CFGetTypeID(expiry) != CFBooleanGetTypeID(),
                  expiry.doubleValue.isFinite, expiry.doubleValue / 1000 > date.timeIntervalSince1970 else { return nil }
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { return nil }
            let metadata = try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": entry])
            return (token, metadata.flatMap { ClaudeCredentialSource.plan(in: $0) })
        }
        // Ambiguity must never select an arbitrary organization or account.
        return accounts.count == 1 ? accounts.first : nil
    }

    static func account() -> (token: String, plan: String?)? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/config.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
              let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountID = config["lastKnownAccountUuid"] as? String,
              let encoded = config["oauth:tokenCacheV2"] as? String,
              let encrypted = Data(base64Encoded: encoded) else { return nil }
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "Claude Safe Storage", kSecAttrAccount: "Claude Key",
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let password = result as? Data,
              let clear = decrypt(encrypted, password: password),
              let account = decode(in: clear, accountID: accountID) else { return nil }
        // Discard results if Desktop switched identity while Keychain access was pending.
        guard let fresh = try? Data(contentsOf: url), fresh == data else { return nil }
        return account
    }
}

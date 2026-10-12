import XCTest
import CommonCrypto
@testable import QuotaCore

final class ClaudeDesktopTests: XCTestCase {
    private let account = "11111111-1111-1111-1111-111111111111"
    private func cache(account: String? = nil, expiry: Any = 200000, scope: String = "user:profile", host: String = "https://api.anthropic.com", count: Int = 1) throws -> Data {
        var entries: [String: Any] = [:]
        for i in 0..<count {
            entries["acct:\(account ?? self.account)|client:org\(i):\(host):\(scope)"] = ["token": "fixture-secret", "expiresAt": expiry, "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x"]
        }
        return try JSONSerialization.data(withJSONObject: entries)
    }
    func testDesktopIdentityScopeAndExpiry() throws {
        let now = Date(timeIntervalSince1970: 100)
        let decoded = ClaudeDesktopCredentials.decode(in: try cache(), accountID: account, at: now)
        XCTAssertEqual(decoded?.token, "fixture-secret")
        XCTAssertEqual(decoded?.plan, "Max 5x")
        for data in [try cache(account: "22222222-2222-2222-2222-222222222222"), try cache(expiry: 100000), try cache(expiry: true), try cache(scope: "user:inference"), try cache(host: "https://example.invalid"), try cache(count: 2), Data("{}".utf8)] {
            XCTAssertNil(ClaudeDesktopCredentials.decode(in: data, accountID: account, at: now))
        }
    }
    func testEncryptionRoundTripAndFailures() throws {
        let password = Array("fixture-only-password".utf8), salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: 16)
        password.withUnsafeBytes { raw in
            XCTAssertEqual(CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), raw.baseAddress!.assumingMemoryBound(to: CChar.self), password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, 16), Int32(kCCSuccess))
        }
        let clear = try cache(), input = Array(clear), iv = [UInt8](repeating: 32, count: 16)
        var output = [UInt8](repeating: 0, count: input.count + 16), count = 0
        XCTAssertEqual(CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key, 16, iv, input, input.count, &output, output.count, &count), Int32(kCCSuccess))
        let encrypted = Data("v10".utf8) + Data(output.prefix(count))
        XCTAssertEqual(ClaudeDesktopCredentials.decrypt(encrypted, password: Data(password)), clear)
        XCTAssertNil(ClaudeDesktopCredentials.decrypt(encrypted, password: Data("wrong".utf8)))
        XCTAssertNil(ClaudeDesktopCredentials.decrypt(Data("v11".utf8) + encrypted.dropFirst(3), password: Data(password)))
        XCTAssertNil(ClaudeDesktopCredentials.decrypt(Data("v10".utf8), password: Data(password)))
    }
}

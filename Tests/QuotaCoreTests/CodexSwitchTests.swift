import XCTest
@testable import QuotaCore

final class CodexSwitchTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var vault: SwitchVault!
    private var old: ProviderAccount!
    private var target: ProviderAccount!
    private var original: Data!
    private var destination: Data!
    private var transaction: CodexSwitchTransaction {
        .init(root: root, active: CodexActiveLogin(home: home), vault: vault)
    }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("switch-test-" + UUID().uuidString)
        home = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        vault = SwitchVault()
        original = try auth("old", token: "old-refresh")
        destination = try auth("new", token: "new-refresh")
        old = ProviderAccount(signature: "Old", identityKey: try CodexCredential(original).identityKey, connection: .currentSession)
        target = ProviderAccount(signature: "New", identityKey: try CodexCredential(destination).identityKey, connection: .independent)
        try original.write(to: home.appendingPathComponent("auth.json"))
        try Data("cli_auth_credentials_store = 'file'\n".utf8).write(to: home.appendingPathComponent("config.toml"))
        try vault.save(destination, id: target.id)
        try JSONEncoder().encode([old!, target!]).write(to: root.appendingPathComponent("accounts.json"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func auth(_ id: String, token: String) throws -> Data {
        let claims: [String: Any] = ["sub": "person", "https://api.openai.com/auth": ["chatgpt_account_id": id]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["account_id": id,
            "access_token": "access", "id_token": "h.\(payload).s", "refresh_token": token]])
    }
    private func live() throws -> Data { try Data(contentsOf: home.appendingPathComponent("auth.json")) }
    private func commit(_ tx: CodexSwitchTransaction? = nil) throws -> [ProviderAccount] {
        try (tx ?? transaction).commit(to: target.id, accounts: [old!, target!], expectedCurrentIdentity: old.identityKey)
    }
    func testSwitchPreservesOldLoginAndRoundTripUsesLatestActiveTokens() throws {
        let config = try Data(contentsOf: home.appendingPathComponent("config.toml"))
        let next = try commit()
        XCTAssertEqual(try live(), destination)
        XCTAssertEqual(try vault.read(old.id), original)
        XCTAssertEqual(next.first { $0.id == old.id }?.connection, .independent)
        XCTAssertEqual(next.first { $0.id == target.id }?.credentialsHandedToCodex, true)
        let rotated = try auth("new", token: "new-refresh-rotated-by-codex")
        try rotated.write(to: home.appendingPathComponent("auth.json"))
        let back = try transaction.commit(to: old.id, accounts: next, expectedCurrentIdentity: target.identityKey)
        XCTAssertEqual(try live(), original)
        XCTAssertEqual(try vault.read(target.id), rotated)
        XCTAssertNil(back.first { $0.id == target.id }?.credentialsHandedToCodex)
        XCTAssertEqual(back.first { $0.id == old.id }?.credentialsHandedToCodex, true)
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("config.toml")), config)
        let attrs = try FileManager.default.attributesOfItem(atPath: home.appendingPathComponent("auth.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(transaction.isPending)
        XCTAssertNil(try vault.read(CodexSwitchTransaction.journalID))
    }
    func testUnsavedCurrentLoginIsAddedWithoutLosingSwitchBackCredentials() throws {
        let next = try transaction.commit(to: target.id, accounts: [target!], expectedCurrentIdentity: old.identityKey)
        let preserved = try XCTUnwrap(next.first { $0.identityKey == old.identityKey })
        XCTAssertEqual(try vault.read(preserved.id), original)
        XCTAssertTrue(ProviderAccount.validSignature(preserved.signature))
        XCTAssertEqual(preserved.connection, .independent)
    }
    func testEachFailureCheckpointRestoresAuthRegistryAndVault() throws {
        for stage in [CodexSwitchTransaction.Stage.prepared, .vaultsSaved, .activeWritten, .registryWritten] {
            var tx = transaction
            tx.checkpoint = { if $0 == stage { throw AccountError.storage } }
            XCTAssertThrowsError(try commit(tx))
            XCTAssertEqual(try live(), original)
            XCTAssertNil(try vault.read(old.id))
            XCTAssertEqual(try vault.read(target.id), destination)
            let accounts = try JSONDecoder().decode([ProviderAccount].self, from: Data(contentsOf: root.appendingPathComponent("accounts.json")))
            XCTAssertEqual(accounts, [old!, target!])
            XCTAssertFalse(transaction.isPending)
        }
    }
    func testKeychainUnavailableCannotReplaceActiveLogin() throws {
        vault.failWrites = true
        XCTAssertThrowsError(try commit())
        XCTAssertEqual(try live(), original)
        vault.failWrites = false
        try transaction.recover()
        XCTAssertFalse(transaction.isPending)
    }
    func testFileModesAndWorkspaceRestrictionsAreNotBypassed() throws {
        for text in ["cli_auth_credentials_store = 'keyring'", "\"cli_auth_credentials_store\" = \"auto\"", "cli_auth_credentials_store = 'ephemeral'", "forced_login_method = 'api'", "forced_chatgpt_workspace_id = 'different'"] {
            try Data(text.utf8).write(to: home.appendingPathComponent("config.toml"))
            XCTAssertThrowsError(try commit())
            XCTAssertEqual(try live(), original)
            XCTAssertFalse(transaction.isPending)
        }
    }
    func testSymlinkAuthIsRejectedWithoutChangingItsTarget() throws {
        let other = root.appendingPathComponent("other.json")
        try original.write(to: other)
        try FileManager.default.removeItem(at: home.appendingPathComponent("auth.json"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("auth.json"), withDestinationURL: other)
        XCTAssertThrowsError(try commit())
        XCTAssertEqual(try Data(contentsOf: other), original)
    }
    func testUnrecognizedCredentialSettingSyntaxCannotBeSilentlyIgnored() throws {
        for text in [
            "profiles.work.cli_auth_credentials_store = 'keyring'",
            "profiles.work = { cli_auth_credentials_store = 'keyring' }",
            "profiles.work.forced_login_method = 'api'",
            "profiles.work = { forced_chatgpt_workspace_id = 'different' }"
        ] {
            try Data(text.utf8).write(to: home.appendingPathComponent("config.toml"))
            XCTAssertThrowsError(try commit())
            XCTAssertEqual(try live(), original)
            XCTAssertFalse(transaction.isPending)
        }
        let comments = "# cli_auth_credentials_store = 'keyring'\nmodel = 'example' # forced_login_method = 'api'\ncli_auth_credentials_store = 'file'\n"
        try Data(comments.utf8).write(to: home.appendingPathComponent("config.toml"))
        XCTAssertNoThrow(try commit())
    }
    func testChangedOrInvalidIdentityCannotOverwriteCurrentLogin() throws {
        try auth("elsewhere", token: "other-token").write(to: home.appendingPathComponent("auth.json"))
        let other = try live()
        XCTAssertThrowsError(try commit())
        XCTAssertEqual(try live(), other)
        try original.write(to: home.appendingPathComponent("auth.json"))
        try vault.save(try auth("wrong-target", token: "wrong"), id: target.id)
        XCTAssertThrowsError(try commit())
        XCTAssertEqual(try live(), original)
    }
    func testCrashRecoveryFinishesHandoffWithoutOverwritingNewerCodexTokens() throws {
        var tx = transaction
        let captured = CapturedJournal()
        tx.checkpoint = { [vault] stage in
            if stage == .activeWritten {
                captured.data = try vault!.read(CodexSwitchTransaction.journalID)
                throw AccountError.storage
            }
        }
        XCTAssertThrowsError(try commit(tx)) // Capture a mid-transaction journal using only fixtures.
        try vault.save(XCTUnwrap(captured.data), id: CodexSwitchTransaction.journalID)
        try Data("pending".utf8).write(to: root.appendingPathComponent("switch.pending"))
        let latest = try auth("new", token: "codex-refreshed-after-crash")
        try latest.write(to: home.appendingPathComponent("auth.json"))
        try transaction.recover()
        XCTAssertEqual(try live(), latest)
        XCTAssertEqual(try vault.read(old.id), original)
        let accounts = try JSONDecoder().decode([ProviderAccount].self, from: Data(contentsOf: root.appendingPathComponent("accounts.json")))
        XCTAssertEqual(accounts.first { $0.id == target.id }?.credentialsHandedToCodex, true)
        XCTAssertFalse(transaction.isPending)
    }
    func testCancelledPreparationRestoresNoActiveLoginFile() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent("auth.json"))
        var tx = transaction
        tx.checkpoint = { if $0 == .activeWritten { throw CancellationError() } }
        XCTAssertThrowsError(try tx.commit(to: target.id, accounts: [target!], expectedCurrentIdentity: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
        XCTAssertFalse(transaction.isPending)
    }
    func testCrashBeforeAuthWriteRollsBackPreparedVaultChanges() throws {
        let captured = CapturedJournal()
        var tx = transaction
        tx.checkpoint = { [vault] stage in
            if stage == .vaultsSaved {
                captured.data = try vault!.read(CodexSwitchTransaction.journalID)
                throw AccountError.storage
            }
        }
        XCTAssertThrowsError(try commit(tx))
        try vault.save(XCTUnwrap(captured.data), id: CodexSwitchTransaction.journalID)
        try vault.save(original, id: old.id)
        try Data("pending".utf8).write(to: root.appendingPathComponent("switch.pending"))
        try transaction.recover()
        XCTAssertEqual(try live(), original)
        XCTAssertNil(try vault.read(old.id))
        XCTAssertFalse(transaction.isPending)
    }
}

private final class CapturedJournal: @unchecked Sendable { var data: Data? }
private final class SwitchVault: AccountCredentialVault, @unchecked Sendable {
    var failWrites = false
    private var values: [UUID: Data] = [:]
    func read(_ id: UUID) throws -> Data? { values[id] }
    func save(_ data: Data, id: UUID) throws {
        if failWrites { throw AccountError.storage }; values[id] = data
    }
    func delete(_ id: UUID) throws { values[id] = nil }
}

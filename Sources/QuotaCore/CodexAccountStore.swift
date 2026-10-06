import Foundation
import Security
import Darwin
import CryptoKit

protocol AccountCredentialVault: Sendable {
    func read(_ id: UUID) throws -> Data?
    func save(_ data: Data, id: UUID) throws
    func delete(_ id: UUID) throws
}
struct CodexAccountKeychain: AccountCredentialVault {
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.quotaclock.accounts.v1",
         kSecAttrAccount as String: "codex.\(id.uuidString)", kSecAttrSynchronizable as String: false]
    }
    private func checkHost() throws {
        guard Bundle.main.bundleIdentifier == "com.quotaclock.app" else { throw AccountError.storage }
    }
    func read(_ id: UUID) throws -> Data? {
        try checkHost()
        var query = query(id); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw AccountError.storage }
        return data
    }
    func save(_ data: Data, id: UUID) throws {
        try checkHost()
        let update = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AccountError.storage }
        var query = query(id); query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AccountError.storage }
    }
    func delete(_ id: UUID) throws {
        try checkHost()
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.storage }
    }
}

/// Locks are held across await by an owned object, and also exclude another QuotaClock process.
final class AccountLease: @unchecked Sendable {
    private let fd: Int32
    init(_ url: URL, shared: Bool = false) throws {
        fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AccountError.storage }
        guard flock(fd, (shared ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else { close(fd); throw AccountError.busy }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
}

/// Owns all credential mutation. UI and adapters never receive secret material.
public actor CodexAccountStore {
    private let root: URL
    private let vault: any AccountCredentialVault
    private let active: CodexActiveLogin
    private let rpc: IsolatedCodexRPC
    private var inFlight: Set<UUID> = []
    private var switchRequested = false
    private var monitoringTasks: [UUID: Task<CodexAccountData?, Error>] = [:]
    public init() {
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuotaClock/Accounts")
        vault = CodexAccountKeychain(); active = CodexActiveLogin(); rpc = IsolatedCodexRPC()
    }
    init(root: URL, vault: any AccountCredentialVault, active: CodexActiveLogin, rpc: IsolatedCodexRPC) {
        self.root = root; self.vault = vault; self.active = active; self.rpc = rpc
    }
    private func prepare() throws { try Self.directory(root) }
    private static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw AccountError.storage }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private var registryURL: URL { root.appendingPathComponent("accounts.json") }
    private var switchTransaction: CodexSwitchTransaction { .init(root: root, active: active, vault: vault) }
    private func operationLease() throws -> AccountLease {
        guard !switchRequested else { throw AccountError.busy }
        try prepare()
        let lease = try AccountLease(root.appendingPathComponent("operations.lock"), shared: true)
        guard !switchTransaction.isPending else { throw CodexSwitchError.recoveryRequired }
        return lease
    }
    private func readRegistry() throws -> [ProviderAccount] {
        guard FileManager.default.fileExists(atPath: registryURL.path) else { return [] }
        let data = try Data(contentsOf: registryURL)
        guard data.count < 262_144 else { throw AccountError.storage }
        let accounts = try JSONDecoder().decode([ProviderAccount].self, from: data)
        guard Set(accounts.map(\.id)).count == accounts.count, Set(accounts.map(\.identityKey)).count == accounts.count,
              Set(accounts.map { $0.signature.lowercased() }).count == accounts.count,
              accounts.allSatisfy({ $0.providerID == "codex" && ProviderAccount.validSignature($0.signature) }) else { throw AccountError.storage }
        return accounts
    }
    private func updateRegistry(_ update: (inout [ProviderAccount]) throws -> Void) throws {
        try prepare()
        let lease = try AccountLease(root.appendingPathComponent("registry.lock"))
        defer { withExtendedLifetime(lease) {} }
        var accounts = try readRegistry(); try update(&accounts)
        try Self.write(JSONEncoder().encode(accounts), to: registryURL)
    }
    public func accounts() throws -> [ProviderAccount] {
        try prepare()
        if switchTransaction.isPending {
            let lease = try AccountLease(root.appendingPathComponent("operations.lock"))
            defer { withExtendedLifetime(lease) {} }
            try switchTransaction.recover()
        }
        // Uncommitted new logins have no existing refresh lineage to recover. Remove them once
        // both their owning app and child have exited; saved-account sessions are recovered separately.
        if let lease = try? AccountLease(root.appendingPathComponent("login.lock")) {
            defer { withExtendedLifetime(lease) {} }
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix("login-") {
                if (try? ensureWriterStopped(url)) != nil { try FileManager.default.removeItem(at: url) }
            }
        }
        return try readRegistry()
    }
    public func currentIdentity() -> String? { active.identityKey() }
    /// A changed access token allows a previously expired link to retry automatically.
    /// Exposes a one-way revision only; the UI never receives an access or refresh token.
    public func currentCredentialRevision() -> String? {
        guard let credential = try? active.credential() else { return nil }
        return SHA256.hash(data: Data(credential.accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func linkCurrent(signature: String) throws -> ProviderAccount {
        let operation = try operationLease(); defer { withExtendedLifetime(operation) {} }
        guard ProviderAccount.validSignature(signature) else { throw AccountError.invalidSignature }
        let credential = try active.credential()
        let account = ProviderAccount(signature: signature, identityKey: credential.identityKey, email: credential.email,
                                      plan: credential.plan, connection: .currentSession)
        try updateRegistry { accounts in
            guard !accounts.contains(where: { $0.identityKey == account.identityKey || $0.signature.lowercased() == signature.lowercased() }) else { throw AccountError.duplicate }
            accounts.append(account)
        }
        return account // No Keychain write and no copy of the active refresh token.
    }
    public func rename(_ id: UUID, signature: String) throws {
        let operation = try operationLease(); defer { withExtendedLifetime(operation) {} }
        guard ProviderAccount.validSignature(signature) else { throw AccountError.invalidSignature }
        try updateRegistry { accounts in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.identityChanged }
            guard !accounts.contains(where: { $0.id != id && $0.signature.lowercased() == signature.lowercased() }) else { throw AccountError.duplicate }
            accounts[index].signature = signature
        }
    }
    private func session(_ id: UUID) -> URL { root.appendingPathComponent("sessions/\(id.uuidString)") }
    private func ensureWriterStopped(_ home: URL) throws {
        if let text = try? String(contentsOf: home.appendingPathComponent("writer.pid")),
           let pid = Int32(text), pid > 0, kill(pid, 0) == 0 { throw AccountError.busy }
    }
    private func acquire(_ id: UUID) throws -> AccountLease {
        try prepare()
        guard !inFlight.contains(id) else { throw AccountError.busy }
        return try AccountLease(root.appendingPathComponent("\(id.uuidString).lock"))
    }
    public func remove(_ id: UUID) throws {
        let operation = try operationLease(); defer { withExtendedLifetime(operation) {} }
        let lease = try acquire(id); defer { withExtendedLifetime(lease) {} }
        try ensureWriterStopped(session(id))
        try vault.delete(id)
        try updateRegistry { $0.removeAll { $0.id == id } }
        if FileManager.default.fileExists(atPath: session(id).path) { try FileManager.default.removeItem(at: session(id)) }
        // Removing a monitor never revokes any Codex session.
    }
    /// Reconcile on both success and failure, including recovery after a crash/Keychain outage.
    private func reconcile(_ account: ProviderAccount, home: URL) throws {
        try ensureWriterStopped(home)
        let path = home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: path.path) else { throw AccountError.recoveryRequired }
        do {
            let credential = try CodexCredential(Data(contentsOf: path))
            guard credential.identityKey == account.identityKey, credential.refreshToken?.isEmpty == false else { throw AccountError.identityChanged }
            try vault.save(credential.data, id: account.id)
        } catch { throw AccountError.recoveryRequired }
        try FileManager.default.removeItem(at: home)
    }
    public func signIn(signature: String, replacing id: UUID? = nil,
                       show: @escaping @Sendable (CodexSignInPrompt) -> Void) async throws -> ProviderAccount {
        guard ProviderAccount.validSignature(signature) else { throw AccountError.invalidSignature }
        let saved = try accounts()
        let operation = try operationLease(); defer { withExtendedLifetime(operation) {} }
        let previous = id.flatMap { id in saved.first { $0.id == id } }
        if id != nil && previous == nil { throw AccountError.identityChanged }
        guard !saved.contains(where: { $0.id != id && $0.signature.lowercased() == signature.lowercased() }) else { throw AccountError.duplicate }
        let accountID = id ?? UUID()
        let lease = try acquire(accountID)
        let loginLease = try AccountLease(root.appendingPathComponent("login.lock"))
        defer { withExtendedLifetime((lease, loginLease)) {} }
        inFlight.insert(accountID); defer { inFlight.remove(accountID) }
        // Never overwrite an uncommitted rotated credential with a fresh login.
        if let previous, FileManager.default.fileExists(atPath: session(accountID).path) {
            try reconcile(previous, home: session(accountID))
        }
        let home = root.appendingPathComponent("login-\(UUID().uuidString)")
        try Self.directory(home)
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try await rpc.run(home: home, operation: .login(show))
        try Task.checkCancellation()
        let credential = try CodexCredential(Data(contentsOf: home.appendingPathComponent("auth.json")))
        guard credential.refreshToken?.isEmpty == false else { throw ProviderFetchError.authenticationRequired }
        if let previous, previous.identityKey != credential.identityKey { throw AccountError.identityChanged }
        // An independently issued session must never be the active session's token lineage.
        if let live = try? active.credential(), live.refreshToken == credential.refreshToken { throw AccountError.identityChanged }
        let account = ProviderAccount(id: accountID, signature: signature, identityKey: credential.identityKey,
                                      email: credential.email, plan: credential.plan, connection: .independent)
        try updateRegistry { accounts in
            guard !accounts.contains(where: { $0.id != accountID && ($0.identityKey == account.identityKey || $0.signature.lowercased() == signature.lowercased()) }) else { throw AccountError.duplicate }
            try vault.save(credential.data, id: account.id)
            if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account }
            else { accounts.append(account) }
        }
        return account
    }
    private func monitorRead(_ id: UUID, home: URL, credential: CodexCredential?) async throws -> CodexAccountData? {
        let rpc = rpc
        let task = Task { try await rpc.run(home: home, operation: .read(credential)) }
        monitoringTasks[id] = task
        defer { monitoringTasks[id] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func fetch(_ id: UUID, at date: Date) async throws -> ProductQuota {
        let operation = try operationLease(); defer { withExtendedLifetime(operation) {} }
        let lease = try acquire(id); defer { withExtendedLifetime(lease) {} }
        guard let account = try readRegistry().first(where: { $0.id == id }) else { throw AccountError.identityChanged }
        inFlight.insert(id); defer { inFlight.remove(id) }
        let home = session(id)
        let data: CodexAccountData
        if account.connection == .currentSession || account.credentialsHandedToCodex == true {
            let credential = try active.credential()
            guard credential.identityKey == account.identityKey else { throw AccountError.currentLoginUnavailable }
            try Self.directory(home)
            // A linked session must always start empty, with no persisted managed credentials.
            if FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path) { throw AccountError.recoveryRequired }
            defer { try? FileManager.default.removeItem(at: home) }
            guard let result = try await monitorRead(id, home: home, credential: credential) else { throw ProviderFetchError.invalidResponse }
            guard active.identityKey() == account.identityKey else { throw AccountError.currentLoginUnavailable }
            data = result
        } else {
            if FileManager.default.fileExists(atPath: home.path) { try reconcile(account, home: home) }
            guard let raw = try vault.read(id) else { throw ProviderFetchError.authenticationRequired }
            let credential = try CodexCredential(raw)
            guard credential.identityKey == account.identityKey else { throw AccountError.identityChanged }
            if let live = try? active.credential(), live.refreshToken == credential.refreshToken { throw AccountError.identityChanged }
            try Self.directory(home)
            try Self.write(raw, to: home.appendingPathComponent("auth.json"))
            let result: Result<CodexAccountData?, Error>
            do { result = .success(try await monitorRead(id, home: home, credential: nil)) }
            catch { result = .failure(error) }
            // The child has exited. Even a failed quota read can have rotated its token.
            try reconcile(account, home: home)
            guard let value = try result.get() else { throw ProviderFetchError.invalidResponse }
            data = value
        }
        try Task.checkCancellation()
        var quota = try CodexQuotaParser.parse(data.rateLimits, at: date)
        if let usage = data.usage { quota.usage = try? CodexUsageParser.parse(usage) }
        var product = ProductMigration.product(quota)
        product.id = account.productID
        // A rename during the network request must not resurrect the previous signature.
        let latest = try readRegistry().first { $0.id == id } ?? account
        product.account = latest.presentation(currentIdentity: active.identityKey())
        return product
    }

    /// This is the sole explicit write path to the user's active Codex login.
    /// The caller supplies a graceful Desktop stop; tests supply a no-op closure.
    public func switchAccount(to id: UUID, expectedCurrentIdentity: String?,
                              stopCodex: @Sendable () async throws -> Void) async throws -> [ProviderAccount] {
        guard !switchRequested else { throw AccountError.busy }
        switchRequested = true; defer { switchRequested = false }
        for task in monitoringTasks.values { task.cancel() }
        try prepare()
        let deadline = Date().addingTimeInterval(30)
        var operation: AccountLease?
        while operation == nil {
            try Task.checkCancellation()
            do { operation = try AccountLease(root.appendingPathComponent("operations.lock")) }
            catch AccountError.busy {
                guard Date() < deadline else { throw AccountError.busy }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { withExtendedLifetime(operation) {} }
        try switchTransaction.recover()
        let saved = try readRegistry()
        guard let account = saved.first(where: { $0.id == id }) else { throw AccountError.identityChanged }
        let live = try switchTransaction.readActive()
        guard live?.identityKey == expectedCurrentIdentity else { throw CodexSwitchError.loginChanged }
        if live?.identityKey == account.identityKey { return saved }
        guard account.connection == .independent, account.credentialsHandedToCodex != true else {
            throw CodexSwitchError.signInFirst
        }
        // Recover every earlier monitor write before the handoff can replace a
        // vault entry. An old session must never restore stale tokens afterwards.
        for savedAccount in saved {
            let pendingHome = session(savedAccount.id)
            if FileManager.default.fileExists(atPath: pendingHome.path) {
                try ensureWriterStopped(pendingHome)
                if savedAccount.connection == .independent && savedAccount.credentialsHandedToCodex != true {
                    try reconcile(savedAccount, home: pendingHome)
                } else if !FileManager.default.fileExists(atPath: pendingHome.appendingPathComponent("auth.json").path) {
                    try FileManager.default.removeItem(at: pendingHome)
                } else { throw AccountError.recoveryRequired }
            }
        }
        // Validate/refresh the target before stopping Desktop. Reconcile any
        // rotated token even on error, exactly as for independent monitoring.
        let home = session(id)
        if FileManager.default.fileExists(atPath: home.path) { try reconcile(account, home: home) }
        guard let raw = try vault.read(id) else { throw CodexSwitchError.signInFirst }
        let credential = try CodexCredential(raw)
        guard credential.identityKey == account.identityKey, credential.refreshToken?.isEmpty == false,
              live?.refreshToken != credential.refreshToken else { throw AccountError.identityChanged }
        try Self.directory(home)
        try Self.write(raw, to: home.appendingPathComponent("auth.json"))
        let validation: Result<CodexAccountData?, Error>
        do { validation = .success(try await rpc.run(home: home, operation: .read(nil, usage: false))) }
        catch { validation = .failure(error) }
        try reconcile(account, home: home)
        _ = try validation.get()
        guard let refreshed = try vault.read(id) else { throw CodexSwitchError.signInFirst }
        try switchTransaction.validateTarget(CodexCredential(refreshed))
        try Task.checkCancellation()
        try await stopCodex()
        try Task.checkCancellation()
        // Re-read after Desktop exits, so its final token rotation is preserved.
        return try switchTransaction.commit(to: id, accounts: try readRegistry(), expectedCurrentIdentity: expectedCurrentIdentity)
    }
}

public struct CodexAccountAdapter: ProductAdapter {
    public let descriptor: ProductDescriptor
    public let presentation: AccountPresentation
    private let store: CodexAccountStore
    public init(account: ProviderAccount, currentIdentity: String?, store: CodexAccountStore) {
        descriptor = account.descriptor; presentation = account.presentation(currentIdentity: currentIdentity); self.store = store
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        do { return try await store.fetch(presentation.id, at: date) }
        catch AccountError.currentLoginUnavailable { throw ProviderFetchError.authenticationRequired }
        catch AccountError.identityChanged { throw ProviderFetchError.authenticationRequired }
    }
}

import XCTest
@testable import QuotaCore

final class MultiAccountTests: XCTestCase {
    private var root: URL!
    private var activeHome: URL!
    private var vault: MemoryAccountVault!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("quotaclock-test-" + UUID().uuidString)
        activeHome = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try auth(account: "active", token: "active-refresh").write(to: activeHome.appendingPathComponent("auth.json"))
        try Data("unrelated-active-config".utf8).write(to: activeHome.appendingPathComponent("config.toml"))
        vault = MemoryAccountVault()
        let executable = root.appendingPathComponent("fake-codex")
        try Data(Self.server.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func auth(account: String = "work", token: String = "work-refresh", subject: String = "user", email: String = "private@example.test") throws -> Data {
        let claims: [String: Any] = ["sub": subject, "email": email, "https://api.openai.com/auth": ["chatgpt_account_id": account, "chatgpt_plan_type": "plus"]]
        let body = try JSONSerialization.data(withJSONObject: claims).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["id_token": "header.\(body).sig", "access_token": "access.\(body).sig", "refresh_token": token, "account_id": account], "last_refresh": "2026-09-28T00:00:00Z"])
    }
    private func configure(_ mode: String = "success", credential: Data? = nil) throws {
        let credential = try credential ?? auth()
        try JSONSerialization.data(withJSONObject: ["mode": mode, "auth": JSONSerialization.jsonObject(with: credential)])
            .write(to: root.appendingPathComponent("fixture.json"), options: .atomic)
    }
    // macOS may cold-start the Python fixture slowly. Timeout-specific cases still
    // inject a one-second budget; normal transaction tests do not test process startup speed.
    private func store(timeout: TimeInterval = 5) -> CodexAccountStore {
        CodexAccountStore(root: root.appendingPathComponent("store"), vault: vault, active: CodexActiveLogin(home: activeHome),
                          rpc: IsolatedCodexRPC(executable: root.appendingPathComponent("fake-codex").path, timeout: timeout))
    }
    private func signIn(_ store: CodexAccountStore, signature: String = "Work") async throws -> ProviderAccount {
        try await store.signIn(signature: signature, show: { _ in })
    }
    private func activeFiles() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: activeHome.path).map { ($0, try Data(contentsOf: activeHome.appendingPathComponent($0))) })
    }
    private func audit() -> [[String: Any]] {
        guard let data = try? String(contentsOf: root.appendingPathComponent("audit.jsonl")) else { return [] }
        return data.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
    func testSignatureRulesAndStableIdentityExcludeEmail() throws {
        for value in ["Carey", "Work", "Abcdefghijkl"] { XCTAssertTrue(ProviderAccount.validSignature(value)) }
        for value in ["", "Work2", "工作", "A B", " abc", "a@b", "Abcdefghijklm"] { XCTAssertFalse(ProviderAccount.validSignature(value)) }
        let a = try CodexCredential(auth(email: "old@test")), b = try CodexCredential(auth(email: "new@test"))
        XCTAssertEqual(a.identityKey, b.identityKey)
        XCTAssertNotEqual(a.identityKey, try CodexCredential(auth(subject: "other")).identityKey)
        XCTAssertNotEqual(a.identityKey, try CodexCredential(auth(account: "workspace2")).identityKey)
    }
    func testLinkedReadsHaveNoRefreshTokenAndLeaveActiveFilesByteIdentical() async throws {
        try configure()
        let before = try activeFiles(), store = store()
        let account = try await store.linkCurrent(signature: "Carey")
        let product = try await store.fetch(account.id, at: .now)
        XCTAssertEqual(product.account?.signature, "Carey"); XCTAssertEqual(product.account?.isCurrent, true)
        XCTAssertEqual(product.primary()?.value, 74.5)
        XCTAssertEqual(try activeFiles(), before)
        XCTAssertNil(try vault.read(account.id))
        XCTAssertFalse(audit().contains { ($0["params"] as? [String: Any])?["refreshToken"] as? Bool == true })
        let login = try XCTUnwrap(audit().first { $0["method"] as? String == "account/login/start" })
        XCTAssertEqual(login["paramKeys"] as? [String], ["accessToken", "chatgptAccountId", "chatgptPlanType", "type"])
        XCTAssertEqual(login["authExists"] as? Bool, false)
        XCTAssertFalse(audit().contains { $0["home"] as? String == activeHome.path })
        XCTAssertTrue(audit().allSatisfy { $0["fileStorage"] as? Bool == true })
        let reloaded = try await self.store().accounts()
        XCTAssertEqual(reloaded, [account])
    }
    func testIndependentLoginAndRotationNeverTouchActiveAndDeduplicate() async throws {
        try configure()
        let before = try activeFiles(), store = store()
        let account = try await signIn(store)
        XCTAssertEqual(account.connection, .independent)
        XCTAssertEqual(audit().first { $0["method"] as? String == "account/login/start" }?["loginType"] as? String, "chatgpt")
        let product = try await store.fetch(account.id, at: .now)
        XCTAssertEqual(product.account?.isCurrent, false)
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh-rotated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("store/sessions/\(account.id.uuidString)").path))
        XCTAssertEqual(try activeFiles(), before)
        do { _ = try await signIn(store, signature: "Backup"); XCTFail("Duplicate identity") } catch AccountError.duplicate {}
    }
    func testRotationSavedEvenWhenQuotaRequestFails() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        try configure("failAfterRotate")
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch ProviderFetchError.unavailable {}
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh-rotated")
    }
    func testBrowserSignInCancellationLeavesActiveAndSavedAccountsUntouched() async throws {
        try configure("loginWaiting")
        let before = try activeFiles(), store = store()
        let (stream, continuation) = AsyncStream<URL>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            return try await store.signIn(signature: "Browser") { continuation.yield($0.url) }
        }
        var received: URL?
        for await url in stream { received = url; task.cancel(); break }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled browser login must not be saved") } catch is CancellationError {}
        XCTAssertEqual(received?.host, "auth.openai.com")
        XCTAssertEqual(try activeFiles(), before)
        let saved = try await store.accounts()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("store").path).contains { $0.hasPrefix("login-") })
    }
    func testBrowserSignInLinksMustBeOfficialHTTPSWithoutEmbeddedCredentials() throws {
        for raw in ["http://auth.openai.com/oauth/authorize", "https://auth.openai.com.example.test/oauth", "https://user@auth.openai.com/oauth", "https://chatgpt.com:9999/oauth", "https://example.test", "https://auth.openai.com/with space"] {
            XCTAssertThrowsError(try CodexSignInPrompt(response: ["loginId": "fixture", "authUrl": raw]))
        }
        for raw in ["https://auth.openai.com/oauth/authorize?state=fixture", "https://chatgpt.com/oauth/authorize?state=fixture"] {
            XCTAssertEqual(try CodexSignInPrompt(response: ["loginId": "fixture", "authUrl": raw]).url.absoluteString, raw)
        }
        XCTAssertThrowsError(try CodexSignInPrompt(response: ["loginId": "", "authUrl": "https://auth.openai.com/oauth"]))
    }
    func testCancellationSavesRotationAndReapsProcess() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        try configure("hangAfterRotate")
        let task = Task { try await store.fetch(account.id, at: .now) }
        for _ in 0..<100 {
            if audit().contains(where: { $0["method"] as? String == "account/rateLimits/read" }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError {}
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh-rotated")
        try configure(); _ = try await store.fetch(account.id, at: .now)
    }
    func testSwitchCancelsSlowMonitorReconcilesRotationAndSkipsUsage() async throws {
        try configure(); let store = store(timeout: 20), account = try await signIn(store)
        let previous = await store.currentIdentity()
        try configure("hangAfterRotate")
        let monitor = Task { try await store.fetch(account.id, at: .now) }
        for _ in 0..<200 {
            if audit().contains(where: { $0["method"] as? String == "account/rateLimits/read" }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try configure()
        let start = Date()
        _ = try await store.switchAccount(to: account.id, expectedCurrentIdentity: previous, stopCodex: {})
        do { _ = try await monitor.value; XCTFail("Monitor must yield its credential lease") } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        let current = await store.currentIdentity()
        XCTAssertEqual(current, account.identityKey)
        XCTAssertFalse(audit().contains { $0["method"] as? String == "account/usage/read" })
        let active = try CodexCredential(Data(contentsOf: activeHome.appendingPathComponent("auth.json")))
        XCTAssertEqual(active.refreshToken, "work-refresh-rotated-rotated")
    }
    func testKeychainFailureRecoversRotatedCredentialBeforeAnotherRequest() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        vault.failSave = true
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch AccountError.recoveryRequired {}
        let pending = root.appendingPathComponent("store/sessions/\(account.id.uuidString)/auth.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: pending.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let calls = audit().count
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch AccountError.recoveryRequired {}
        XCTAssertEqual(audit().count, calls)
        vault.failSave = false
        _ = try await self.store().fetch(account.id, at: .now)
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh-rotated-rotated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
    }
    func testLinkedAccountAfterSwitchFailsWithoutUsingArchivedCredential() async throws {
        try configure(); let store = store(), account = try await store.linkCurrent(signature: "Carey")
        try auth(account: "different").write(to: activeHome.appendingPathComponent("auth.json"))
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch AccountError.currentLoginUnavailable {}
        XCTAssertTrue(audit().isEmpty)
    }
    func testIndependentSessionForCurrentIdentityDoesNotCopyActiveLineage() async throws {
        try configure(credential: auth(account: "active", token: "separate-lineage"))
        let store = store(), before = try activeFiles(), account = try await signIn(store)
        let product = try await store.fetch(account.id, at: .now)
        XCTAssertEqual(product.account?.isCurrent, true)
        XCTAssertEqual(try activeFiles(), before)
    }
    func testSharedRefreshTokenIsRejectedBeforeLaunchingChild() async throws {
        try configure(credential: auth(account: "active", token: "active-refresh"))
        let store = store()
        do { _ = try await signIn(store); XCTFail() } catch AccountError.identityChanged {}
        let accounts = try await store.accounts(); XCTAssertTrue(accounts.isEmpty)
    }
    func testBadRotatedIdentityIsQuarantinedAndDoesNotOverwriteVault() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        try configure("wrongIdentity")
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch AccountError.recoveryRequired {}
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh")
        let calls = audit().count
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch AccountError.recoveryRequired {}
        XCTAssertEqual(audit().count, calls)
    }
    func testConcurrentProcessesCannotRotateSameStoredAccount() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        try configure("hangAfterRotate")
        let task = Task { try await store.fetch(account.id, at: .now) }
        for _ in 0..<100 {
            if audit().contains(where: { $0["method"] as? String == "account/rateLimits/read" }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        do { _ = try await self.store().fetch(account.id, at: .now); XCTFail() } catch AccountError.busy {}
        do { try await store.remove(account.id); XCTFail() } catch AccountError.busy {}
        task.cancel(); _ = try? await task.value
    }
    func testSourceIdentityPersistsAcrossRenameAndRemoveNeverLogsOut() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        let before = try activeFiles()
        try await store.rename(account.id, signature: "cAreY")
        let loaded = try await store.accounts()
        let renamed = try XCTUnwrap(loaded.first)
        XCTAssertEqual(renamed.sourceID, account.sourceID); XCTAssertEqual(renamed.signature, "cAreY")
        let product = try await store.fetch(account.id, at: .now)
        XCTAssertEqual(product.account?.signature, "cAreY")
        try await store.remove(account.id)
        let remaining = try await self.store().accounts(); XCTAssertTrue(remaining.isEmpty)
        XCTAssertNil(try vault.read(account.id)); XCTAssertEqual(try activeFiles(), before)
        XCTAssertFalse(audit().contains { $0["method"] as? String == "account/logout" })
    }
    func testEnvironmentHasNoInheritedCredentialsConfigOrProjects() {
        let home = root.appendingPathComponent("isolated")
        let env = IsolatedCodexRPC.environment(home: home, inherited: ["HOME": "/active", "CODEX_HOME": "/active/codex", "CODEX_API_KEY": "secret", "OPENAI_API_KEY": "secret", "CODEX_ACCESS_TOKEN": "secret", "OPENAI_FEDERATION_RULE_ID": "secret", "OPENAI_IDENTITY_TOKEN_FILE": "/secret", "CODEX_CONFIG": "/wrong", "PATH": "/usr/bin", "HTTPS_PROXY": "http://localhost:1234"])
        XCTAssertEqual(Set(env.keys), Set(["HOME", "CODEX_HOME", "PATH", "HTTPS_PROXY"]))
        XCTAssertEqual(env["CODEX_HOME"], home.path); XCTAssertEqual(env["HOME"], home.path)
    }
    func testNewActiveAccessTokenCanReleaseAuthenticationBackoffWithoutChangingIdentity() async throws {
        try configure("authError")
        let store = store(), account = try await store.linkCurrent(signature: "Carey")
        let revision = await store.currentCredentialRevision()
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = true; prefs.enabledProducts = [account.productID]
        let writer = SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("snapshot.json")), display: SnapshotStore(url: root.appendingPathComponent("display.json")))
        let adapter = CodexAccountAdapter(account: account, currentIdentity: account.identityKey, store: store)
        let coordinator = ProviderRefreshCoordinator(adapters: [adapter], publisher: writer, existing: nil, preferences: prefs)
        await coordinator.refreshAll(manual: true, onUpdate: { _ in })
        let count = audit().count
        await coordinator.refreshAll(manual: false, onUpdate: { _ in })
        XCTAssertEqual(audit().count, count)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: activeHome.appendingPathComponent("auth.json"))) as? [String: Any])
        var tokens = try XCTUnwrap(document["tokens"] as? [String: Any])
        tokens["access_token"] = "new-access-token"; document["tokens"] = tokens
        try JSONSerialization.data(withJSONObject: document).write(to: activeHome.appendingPathComponent("auth.json"))
        let nextRevision = await store.currentCredentialRevision(), identity = await store.currentIdentity()
        XCTAssertNotEqual(revision, nextRevision); XCTAssertEqual(identity, account.identityKey)
        try configure()
        // The main app re-registers linked adapters only when this one-way revision changes.
        await coordinator.register(adapter)
        await coordinator.refreshAll(manual: false, onUpdate: { _ in })
        let next = await coordinator.current()
        XCTAssertEqual(next.providers.first?.health?.state, .healthy)
    }
    func testOldPreferencesDecodeAndModeOffNeverFetchesStoredAccounts() async throws {
        let old = Data(#"{"enabledProducts":["codex.subscription"],"display":{},"menuOrder":["codex"],"saverOrder":["codex"],"showMenuBar":true}"#.utf8)
        var prefs = try JSONDecoder().decode(PlatformPreferences.self, from: old)
        XCTAssertFalse(prefs.codexMultiAccount)
        try configure(); let store = store(), account = try await signIn(store)
        prefs.enabledProducts.insert(account.productID)
        let writer = SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("snapshot.json")), display: SnapshotStore(url: root.appendingPathComponent("display.json")))
        let adapter = CodexAccountAdapter(account: account, currentIdentity: nil, store: store)
        let coordinator = ProviderRefreshCoordinator(adapters: [adapter], publisher: writer, existing: nil, preferences: prefs)
        let calls = audit().count
        await coordinator.refreshAll(manual: true, onUpdate: { _ in })
        XCTAssertEqual(audit().count, calls)
        prefs.codexMultiAccount = true
        _ = try await coordinator.configure(prefs)
        await coordinator.refreshAll(manual: true, onUpdate: { _ in })
        XCTAssertEqual(try writer.shared.read().providers.first?.id, account.sourceID)
    }
    func testThreeAccountsHeroVisibilityProjectionAndNoEmailLeak() async throws {
        let store = store(); var accounts: [ProviderAccount] = []
        for (id, name) in [("work", "Work"), ("backup", "Backup"), ("carey", "Carey")] {
            try configure(credential: auth(account: id, token: id + "-refresh"))
            accounts.append(try await signIn(store, signature: name))
        }
        try configure()
        try auth(account: "backup", token: "active-backup-refresh").write(to: activeHome.appendingPathComponent("auth.json"))
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = true
        prefs.enabledProducts = Set(accounts.map(\.productID))
        prefs.saverOrder = accounts.reversed().map(\.sourceID)
        let writer = SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("snapshot.json")), display: SnapshotStore(url: root.appendingPathComponent("display.json")))
        let coordinator = ProviderRefreshCoordinator(adapters: accounts.map { CodexAccountAdapter(account: $0, currentIdentity: accounts[1].identityKey, store: store) }, publisher: writer, existing: nil, preferences: prefs)
        await coordinator.refreshAll(manual: true, onUpdate: { _ in })
        let snapshot = try await coordinator.setHero(.pinned(providerID: accounts[1].sourceID))
        XCTAssertEqual(snapshot.providers.count, 3); XCTAssertEqual(snapshot.hero?.account?.signature, "Backup")
        XCTAssertEqual(MenuBarIndicator(snapshot: snapshot).providerID, "codex")
        XCTAssertEqual(MenuBarIndicator(snapshot: snapshot).providerName, "Codex Backup")
        XCTAssertEqual(snapshot.forSurface(.screenSaver).providers.map(\.id), accounts.reversed().map(\.sourceID))
        XCTAssertEqual(snapshot.displaySource(id: accounts[0].sourceID, surface: .widget)?.account?.signature, "Work")
        let data = try SnapshotStore.encode(snapshot.displayProjection()), text = String(decoding: data, as: UTF8.self)
        for secret in ["private@example", "refresh_token", "access_token", accounts[0].identityKey] { XCTAssertFalse(text.contains(secret)) }
        var preference = ProviderDisplayPreference(); preference.availableInWidgets = false
        prefs.display[accounts[0].sourceID] = preference
        let hidden = try await coordinator.configure(prefs)
        XCTAssertNil(hidden.displaySource(id: accounts[0].sourceID, surface: .widget))
        prefs.enabledProducts.remove(accounts[1].productID)
        let disabled = try await coordinator.configure(prefs)
        XCTAssertTrue(disabled.pinnedHeroUnavailable); XCTAssertNotEqual(disabled.hero?.id, accounts[1].sourceID)
        XCTAssertNil(disabled.displaySource(id: accounts[1].sourceID, surface: .widget))
        _ = try JSONDecoder().decode(QuotaSnapshot.self, from: data).validated()
    }
    func testCurrentAccountSwitchPublishesCachedHeroWithoutQuotaRequest() async throws {
        let store = store(); var accounts: [ProviderAccount] = []
        for (id, name) in [("work", "Work"), ("backup", "Backup")] {
            try configure(credential: auth(account: id, token: id + "-refresh"))
            accounts.append(try await signIn(store, signature: name))
        }
        try configure()
        try auth(account: "work", token: "active-work").write(to: activeHome.appendingPathComponent("auth.json"))
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = true; prefs.enabledProducts = Set(accounts.map(\.productID))
        prefs.providerDisplay = .init(heroProviderID: "codex")
        let writer = SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("hero.json")), display: SnapshotStore(url: root.appendingPathComponent("hero-display.json")))
        let coordinator = ProviderRefreshCoordinator(adapters: accounts.map { CodexAccountAdapter(account: $0, currentIdentity: accounts[0].identityKey, store: store) }, publisher: writer, existing: nil, preferences: prefs)
        await coordinator.refreshAll(manual: true, onUpdate: { _ in })
        let first = try await coordinator.setHero(.pinned(providerID: accounts[0].sourceID))
        XCTAssertEqual(first.heroSelection, .pinned(providerID: "codex"))
        XCTAssertEqual(first.hero?.account?.signature, "Work")
        // Simulate the external Codex app switching its own login, using a disposable home.
        try auth(account: "backup", token: "active-backup").write(to: activeHome.appendingPathComponent("auth.json"))
        let before = try activeFiles(), calls = audit().count, identity = await store.currentIdentity()
        for account in accounts { await coordinator.register(CodexAccountAdapter(account: account, currentIdentity: identity, store: store)) }
        let switched = try await coordinator.configure(prefs)
        XCTAssertEqual(switched.hero?.account?.signature, "Backup")
        XCTAssertEqual(switched.hero?.primaryMeter?.value, first.providers.first { $0.id == accounts[1].sourceID }?.primaryMeter?.value)
        XCTAssertEqual(try writer.display.read().hero?.account?.signature, "Backup")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: try writer.shared.read(), sourceID: WidgetDisplaySelection.heroID, metric: nil)?.account?.signature, "Backup")
        XCTAssertEqual(audit().count, calls)
        XCTAssertEqual(try activeFiles(), before)
    }
    func testTimeoutAndUnexpectedPeerExitAreBoundedAndRecoverCredentials() async throws {
        try configure(); let initial = store(), account = try await signIn(initial)
        let store = self.store(timeout: 1)
        try configure("hangAfterRotate")
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch ProviderFetchError.timeout {}
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh-rotated")
        try configure("exit")
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch ProviderFetchError.unavailable {}
    }
    func testReadBudgetIsSharedAcrossRPCsAndAllowsRetry() async throws {
        try configure(); let initial = store(), account = try await signIn(initial)
        let bounded = store(timeout: 1)
        try configure("slowEachRead")
        let started = Date()
        do { _ = try await bounded.fetch(account.id, at: .now); XCTFail("RPCs must share one deadline") }
        catch ProviderFetchError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
        try configure()
        let recovered = try await bounded.fetch(account.id, at: .now)
        XCTAssertFalse(recovered.meters.isEmpty)
    }
    func testLinked401NeverRequestsRotation() async throws {
        try configure("authError")
        let store = store(), account = try await store.linkCurrent(signature: "Carey"), before = try activeFiles()
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch ProviderFetchError.authenticationRequired {}
        XCTAssertFalse(audit().contains { ($0["params"] as? [String: Any])?["refreshToken"] as? Bool == true })
        XCTAssertEqual(try activeFiles(), before)
    }
    func testSwitchHandsRefreshOwnershipToCodexAndCanSwitchBack() async throws {
        try configure()
        let store = store(), linked = try await store.linkCurrent(signature: "Main"), target = try await signIn(store)
        let original = try activeFiles()
        _ = try await store.switchAccount(to: target.id, expectedCurrentIdentity: linked.identityKey, stopCodex: {})
        XCTAssertEqual(try CodexCredential(Data(contentsOf: activeHome.appendingPathComponent("auth.json"))).identityKey, target.identityKey)
        let start = audit().count
        _ = try await store.fetch(target.id, at: .now)
        let calls = Array(audit().dropFirst(start))
        XCTAssertTrue(calls.contains { $0["loginType"] as? String == "chatgptAuthTokens" })
        XCTAssertTrue(calls.allSatisfy { $0["authExists"] as? Bool == false })
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(target.id))).refreshToken, "work-refresh-rotated")
        _ = try await store.switchAccount(to: linked.id, expectedCurrentIdentity: target.identityKey, stopCodex: {})
        XCTAssertEqual(try CodexCredential(Data(contentsOf: activeHome.appendingPathComponent("auth.json"))).identityKey, linked.identityKey)
        XCTAssertEqual(try activeFiles()["config.toml"], original["config.toml"])
        let saved = try await store.accounts()
        XCTAssertNil(saved.first { $0.id == target.id }?.credentialsHandedToCodex)
    }
    func testDeclinedDesktopQuitNeverChangesActiveLogin() async throws {
        try configure()
        let store = store(), target = try await signIn(store), before = try activeFiles(), identity = await store.currentIdentity()
        do {
            _ = try await store.switchAccount(to: target.id, expectedCurrentIdentity: identity,
                                               stopCodex: { throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(try activeFiles(), before)
        let saved = try await store.accounts()
        XCTAssertNil(saved.first?.credentialsHandedToCodex)
        // Validation may refresh only the independently owned target.
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(target.id))).refreshToken, "work-refresh-rotated")
    }
    func testHandoffCannotRefreshAnOldCopyAfterAnExternalSwitch() async throws {
        try configure()
        let store = store(), target = try await signIn(store), identity = await store.currentIdentity()
        _ = try await store.switchAccount(to: target.id, expectedCurrentIdentity: identity, stopCodex: {})
        try auth(account: "external", token: "different-session").write(to: activeHome.appendingPathComponent("auth.json"))
        let calls = audit().count
        do { _ = try await store.fetch(target.id, at: .now); XCTFail() } catch AccountError.currentLoginUnavailable {}
        XCTAssertEqual(audit().count, calls)
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(target.id))).refreshToken, "work-refresh-rotated")
    }
    func testSwitchExcludesOtherProcessesAndDetectsChangedLoginAfterQuit() async throws {
        try configure()
        let store = store(), target = try await signIn(store), identity = await store.currentIdentity()
        let second = self.store(), changed = try auth(account: "elsewhere", token: "latest-external")
        let path = activeHome.appendingPathComponent("auth.json")
        do {
            _ = try await store.switchAccount(to: target.id, expectedCurrentIdentity: identity, stopCodex: {
                do { _ = try await second.fetch(target.id, at: .now); XCTFail() } catch AccountError.busy {}
                try changed.write(to: path)
            })
            XCTFail()
        } catch CodexSwitchError.loginChanged {}
        XCTAssertEqual(try Data(contentsOf: path), changed)
        let saved = try await store.accounts()
        XCTAssertNil(saved.first { $0.id == target.id }?.credentialsHandedToCodex)
    }
    func testOwned401RetriesOnceThroughOfficialRefresh() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        try configure("authError")
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch ProviderFetchError.authenticationRequired {}
        XCTAssertEqual(audit().filter { ($0["params"] as? [String: Any])?["refreshToken"] as? Bool == true }.count, 1)
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh-rotated-rotated")
    }
    func testAlternateActiveCredentialStoreNeverUsesLeftoverAuthFile() async throws {
        try Data("cli_auth_credentials_store = \"keyring\"".utf8).write(to: activeHome.appendingPathComponent("config.toml"))
        let store = store()
        do { _ = try await store.linkCurrent(signature: "Carey"); XCTFail() } catch AccountError.currentLoginUnavailable {}
        XCTAssertTrue(audit().isEmpty)
    }
    func testRecoveryWillNotRaceSurvivingChildAfterOwnerExits() async throws {
        try configure(); let store = store(), account = try await signIn(store)
        let home = root.appendingPathComponent("store/sessions/\(account.id.uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try auth().write(to: home.appendingPathComponent("auth.json"))
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: home.appendingPathComponent("writer.pid"))
        let calls = audit().count
        do { _ = try await store.fetch(account.id, at: .now); XCTFail() } catch AccountError.busy {}
        do { try await store.remove(account.id); XCTFail() } catch AccountError.busy {}
        XCTAssertEqual(audit().count, calls)
        XCTAssertEqual(try CodexCredential(XCTUnwrap(vault.read(account.id))).refreshToken, "work-refresh")
    }
    func testAbandonedNewLoginIsCleanedWithoutTouchingSavedCredentials() async throws {
        let home = root.appendingPathComponent("store/login-abandoned")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try auth().write(to: home.appendingPathComponent("auth.json"))
        let accounts = try await store().accounts()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }
    func testOneExpiredAccountDoesNotStopHealthySiblingAndRemovedSourceCannotReappear() async throws {
        try configure(); let store = store(), first = try await signIn(store)
        try configure(credential: auth(account: "backup", token: "backup-refresh"))
        let second = try await signIn(store, signature: "Backup")
        try configure("workFails")
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = true
        prefs.enabledProducts = [first.productID, second.productID]
        let writer = SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("snapshot.json")), display: SnapshotStore(url: root.appendingPathComponent("display.json")))
        let adapters = [first, second].map { CodexAccountAdapter(account: $0, currentIdentity: nil, store: store) }
        let coordinator = ProviderRefreshCoordinator(adapters: adapters, publisher: writer, existing: nil, preferences: prefs)
        await coordinator.refreshAll(manual: true, onUpdate: { _ in })
        let snapshot = await coordinator.current()
        XCTAssertEqual(snapshot.providers.first { $0.id == first.sourceID }?.health?.state, .authenticationRequired)
        XCTAssertEqual(snapshot.providers.first { $0.id == second.sourceID }?.health?.state, .healthy)
        // Simulate a crash after registry deletion but before display preferences were committed.
        let restarted = ProviderRefreshCoordinator(adapters: [adapters[1]], publisher: writer, existing: snapshot, preferences: prefs)
        let next = try await restarted.configure(prefs)
        XCTAssertEqual(next.providers.map(\.id), [second.sourceID])
    }
    private static let server = #"""
#!/usr/bin/python3
import os, sys, json, pathlib, time
base = pathlib.Path(__file__).parent
fixture = json.loads((base / 'fixture.json').read_text())
home = pathlib.Path(os.environ['CODEX_HOME'])
auth = home / 'auth.json'
mode = fixture['mode']
if mode == 'exit': sys.exit(0)
def respond(value): print(json.dumps(value), flush=True)
for line in sys.stdin:
    q = json.loads(line); method = q.get('method'); params = q.get('params', {})
    row = {'method':method,'home':str(home),'paramKeys':sorted(params.keys()),'authExists':auth.exists(), 'loginType':params.get('type'), 'params':{'refreshToken':params.get('refreshToken')}, 'fileStorage':'cli_auth_credentials_store="file"' in sys.argv}
    with (base / 'audit.jsonl').open('a') as log: log.write(json.dumps(row)+'\n')
    if method == 'initialized': continue
    result = {}
    if mode == 'slowEachRead': time.sleep(0.45)
    if method == 'account/login/start' and params.get('type') == 'chatgpt':
        respond({'id':q['id'],'result':{'loginId':'fake-login','authUrl':'https://auth.openai.com/oauth/authorize?state=fixture&code_challenge=fixture'}})
        if mode == 'loginWaiting': time.sleep(30)
        auth.write_text(json.dumps(fixture['auth'])); auth.chmod(0o600)
        respond({'method':'account/login/completed','params':{'loginId':'fake-login','success':True}})
        continue
    if method == 'account/read' and auth.exists():
        value = json.loads(auth.read_text()); value['tokens']['refresh_token'] += '-rotated'
        if mode == 'wrongIdentity': value['tokens']['account_id'] = 'attacker'
        auth.write_text(json.dumps(value)); auth.chmod(0o600)
        result = {'account':{'type':'chatgpt','email':'private@example.test','planType':'plus'}}
    if method == 'account/rateLimits/read':
        if mode == 'hangAfterRotate': time.sleep(30)
        if mode == 'workFails' and auth.exists() and json.loads(auth.read_text())['tokens']['account_id'] == 'work':
            respond({'id':q['id'],'error':{'code':-32000,'message':'401 unauthorized'}}); continue
        if mode in ['failAfterRotate','authError']:
            respond({'id':q['id'],'error':{'code':-32000,'message':'401 unauthorized' if mode == 'authError' else 'network failed'}}); continue
        result = {'rateLimits':{'planType':'plus','primary':{'usedPercent':25.5,'windowDurationMins':300,'resetsAt':1800000000}}}
    if method == 'account/usage/read': result = {'summary':{'lifetimeTokens':1000}}
    respond({'id':q['id'],'result':result})
"""#
}

private final class MemoryAccountVault: AccountCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Data] = [:]
    private var failing = false
    var failSave: Bool { get { lock.lock(); defer { lock.unlock() }; return failing } set { lock.lock(); defer { lock.unlock() }; failing = newValue } }
    func read(_ id: UUID) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[id] }
    func save(_ data: Data, id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        if failing { throw AccountError.storage }; values[id] = data
    }
    func delete(_ id: UUID) throws { lock.lock(); defer { lock.unlock() }; values[id] = nil }
}

import AppKit
@testable import QuotaCore

private final class FixtureVault: AccountCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [UUID: Data] = [:]
    func read(_ id: UUID) throws -> Data? { lock.lock(); defer { lock.unlock() }; return data[id] }
    func save(_ value: Data, id: UUID) throws { lock.lock(); defer { lock.unlock() }; data[id] = value }
    func delete(_ id: UUID) throws { lock.lock(); defer { lock.unlock() }; data[id] = nil }
}
@main struct CheckSwitchIntegration {
    @MainActor static func main() async throws {
        let cli = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = URL(fileURLWithPath: CommandLine.arguments[2])
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("quotaclock-integration-" + UUID().uuidString)
        let home = root.appendingPathComponent("fixture-home")
        let registry = root.appendingPathComponent("registry")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        let vault = FixtureVault()
        func credential(_ name: String) throws -> Data {
            let claims: [String: Any] = ["sub": "fixture", "exp": 4_000_000_000, "https://api.openai.com/auth": ["chatgpt_account_id": name]]
            let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["account_id": name,
                "access_token": "fixture-access", "id_token": "h.\(payload).s", "refresh_token": "fixture-refresh-" + name]])
        }
        let a = try credential("fixture-A"), b = try credential("fixture-B")
        let accountA = ProviderAccount(signature: "Alpha", identityKey: try CodexCredential(a).identityKey, connection: .currentSession)
        let accountB = ProviderAccount(signature: "Beta", identityKey: try CodexCredential(b).identityKey, connection: .independent)
        try a.write(to: home.appendingPathComponent("auth.json"))
        let config = Data("cli_auth_credentials_store = 'file'\n[analytics]\nenabled = false\n".utf8)
        try config.write(to: home.appendingPathComponent("config.toml"))
        try JSONEncoder().encode([accountA, accountB]).write(to: registry.appendingPathComponent("accounts.json"))
        try vault.save(b, id: accountB.id)
        let rpc = root.appendingPathComponent("fixture-rpc")
        try Data("""
        #!/usr/bin/python3
        import sys,json
        for line in sys.stdin:
            m=json.loads(line)
            if 'id' in m: print(json.dumps({'id':m['id'],'result':{}}),flush=True)
        """.utf8).write(to: rpc)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rpc.path)
        let store = CodexAccountStore(root: registry, vault: vault, active: CodexActiveLogin(home: home), rpc: .init(executable: rpc.path))
        let bundleID = "com.quotaclock.switch-fixture"
        func launch(_ url: URL) async throws {
            let config = NSWorkspace.OpenConfiguration(); config.arguments = [home.path]
            config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        var env = CodexDesktopSwitch.Environment.live
        env.applications = {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).compactMap { running in
                running.bundleURL.map { .init(id: running.processIdentifier, url: $0) }
            }
        }
        env.processes = {
            // Strict isolation: the production scanner, restricted to OUR fixture paths.
            try CodexDesktopSwitch.processes().filter { $0.executable.hasPrefix(home.path + "/") || $0.executable.hasPrefix(app.path + "/") }
        }
        env.phaseTimeout = 5
        var events: [String] = []
        func client() -> CodexDesktopSwitch {
            CodexDesktopSwitch(locateApplication: { _ in app }, openApplication: launch,
                               environment: env, home: home, progress: { events.append($0) })
        }
        func awaitAccount(_ id: String) async throws {
            let deadline = Date().addingTimeInterval(10)
            while (try? String(contentsOf: home.appendingPathComponent("desktop-observed-account"))) != id {
                guard Date() < deadline else { fatalError("Fixture Desktop did not load the new profile") }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        do {
            try await CodexDesktopSwitch.runDaemon(cli, command: "start", home: home)
            try await launch(app); try await awaitAccount("fixture-A")
            for (target, previous, expected) in [(accountB, accountA, "fixture-B"), (accountA, accountB, "fixture-A")] {
                let started = Date()
                let desktop = client()
                _ = try desktop.preflight()
                _ = try await store.switchAccount(to: target.id, expectedCurrentIdentity: previous.identityKey) {
                    try await desktop.stop()
                }
                try await desktop.reopen(launchIfClosed: true)
                try await awaitAccount(expected)
                let identity = await store.currentIdentity()
                precondition(identity == target.identityKey)
                print("Native fixture + real isolated daemon: \(expected) loaded after automatic quit, transaction and restart in \(String(format: "%.2f", Date().timeIntervalSince(started)))s.")
            }
            let afterConfig = try Data(contentsOf: home.appendingPathComponent("config.toml"))
            precondition(afterConfig == config)
            print("Round trip passed. Production account store and lifecycle; synthetic credentials/in-memory vault; live user's app and login excluded.")
        } catch {
            print("Isolated integration failed: \(error)")
            // Clean up only the disposable app and daemon, even on failure.
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.forceTerminate() }
            try? await CodexDesktopSwitch.runDaemon(cli, command: "stop", home: home)
            throw error
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.forceTerminate() }
        try await CodexDesktopSwitch.runDaemon(cli, command: "stop", home: home)
        // Stop any surviving test updater, with PID identity verification.
        for managed in CodexDesktopSwitch.managedProcesses(in: try CodexDesktopSwitch.processes(), home: home) {
            try env.signal(managed.process, SIGTERM)
        }
        try FileManager.default.removeItem(at: root)
        print("Isolated test processes and files cleaned up.")
    }
}

import AppKit

@main struct CheckSwitchProcesses {
    @MainActor static func main() throws {
        typealias P = CodexDesktopSwitch.RunningProcess
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("app-server-daemon"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = Data(#"{"pid":101,"processIdentity":{"startSeconds":123,"startMicroseconds":456}}"#.utf8)
        try record.write(to: root.appendingPathComponent("app-server-daemon/daemon.pid"))
        let path = root.appendingPathComponent("packages/app-server-daemon/releases/1/bin/codex").path
        let supervisor = P(id: 100, parent: 1, executable: path, startSeconds: 120, startMicroseconds: 123)
        try Data(#"{"pid":100,"processIdentity":{"startSeconds":120,"startMicroseconds":123}}"#.utf8).write(to: root.appendingPathComponent("app-server-daemon/daemon-updater.pid"))
        let daemon = P(id: 101, parent: 100, executable: path, startSeconds: 123, startMicroseconds: 456)
        let desktop = P(id: 200, parent: 1, executable: "/App/Codex")
        let child = P(id: 201, parent: 200, executable: "/App/codex")
        let external = P(id: 300, parent: 1, executable: "/CLI/codex")
        let all = [supervisor, daemon, desktop, child, external]
        let roots = CodexDesktopSwitch.managedDaemonRoots(in: all, home: root)
        precondition(roots == [100, 101])
        precondition(CodexDesktopSwitch.belongsToDesktop(child, in: all, roots: [200]))
        precondition(!CodexDesktopSwitch.belongsToDesktop(external, in: all, roots: roots.union([200])))
        var reused = daemon; reused.startSeconds = 999
        precondition(CodexDesktopSwitch.managedDaemonRoots(in: [supervisor, reused], home: root) == [100])
        let impostor = P(id: 101, parent: 100, executable: "/CLI/codex", startSeconds: 123, startMicroseconds: 456)
        precondition(CodexDesktopSwitch.managedDaemonRoots(in: [supervisor, impostor], home: root) == [100])
        precondition(!P(id: 2, parent: 1, executable: "browser_crashpad").isCodex)
        for name in ["codex", "codex-cli", "codex-aarch64-ap", "codex-x86_64-app"] {
            precondition(P(id: 2, parent: 1, executable: name).isCodex)
        }
        let cycle = [P(id: 2, parent: 3, executable: "codex"), P(id: 3, parent: 2, executable: "helper")]
        precondition(!CodexDesktopSwitch.belongsToDesktop(cycle[0], in: cycle, roots: [200]))
        print("Process checks passed: managed daemon/supervisor, PID reuse, untrusted path, external CLI, truncated kernel names, ancestry cycle.")
    }
}

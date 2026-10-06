import AppKit

@main struct CheckCodexSwitchLifecycle {
    @MainActor final class Fixture {
        typealias P = CodexDesktopSwitch.RunningProcess
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("qc-lifecycle-" + UUID().uuidString)
        var processes: [P] = []
        var applications: [CodexDesktopSwitch.DesktopApplication] = []
        var events: [String] = []
        var refuseExit = false, stopFailure = false, startFailure = false, lateExternal = false
        var daemon: P!, updater: P!
        init(desktop: Bool = true) throws {
            try FileManager.default.createDirectory(at: home.appendingPathComponent("app-server-daemon"), withIntermediateDirectories: true)
            let path = home.appendingPathComponent("packages/app-server-daemon/releases/fixture/bin/codex").path
            daemon = P(id: 1001, parent: 1, executable: path, startSeconds: 100, startMicroseconds: 1)
            updater = P(id: 1002, parent: 1, executable: path, startSeconds: 100, startMicroseconds: 2)
            for (name, process) in [("daemon.pid", daemon!), ("daemon-updater.pid", updater!)] {
                try JSONSerialization.data(withJSONObject: ["pid": process.id, "processIdentity": ["startSeconds": process.startSeconds, "startMicroseconds": process.startMicroseconds]])
                    .write(to: home.appendingPathComponent("app-server-daemon/" + name))
            }
            processes = [daemon, updater]
            if desktop {
                applications = [.init(id: 2001, url: URL(fileURLWithPath: "/fixture/Codex.app"))]
                processes += [P(id: 2001, parent: 1, executable: "/fixture/Codex", startSeconds: 100),
                              P(id: 2002, parent: 2001, executable: "/fixture/codex", startSeconds: 100)]
            }
        }
        deinit { try? FileManager.default.removeItem(at: home) }
        func client() -> CodexDesktopSwitch {
            let env = CodexDesktopSwitch.Environment(applications: { self.applications }, processes: { self.processes }, signal: { process, signal in
                self.events.append("signal:\(process.id):\(signal)")
                precondition([2001, 2002].contains(process.id), "Only Desktop may be signalled")
                if !self.refuseExit {
                    self.processes.removeAll { $0.id == process.id || $0.parent == process.id }
                    self.applications.removeAll { $0.id == process.id }
                }
            }, runDaemon: { _, command, home in
                precondition(home == self.home)
                self.events.append(command)
                if command == "stop" {
                    if self.stopFailure { throw CocoaError(.fileWriteUnknown) }
                    self.processes.removeAll { $0.id == self.daemon.id }
                    if self.lateExternal { self.processes.append(P(id: 3001, parent: 1, executable: "/other/codex")) }
                } else {
                    if self.startFailure { throw CocoaError(.fileReadUnknown) }
                    self.processes.append(self.daemon)
                }
            }, phaseTimeout: 0.02)
            return CodexDesktopSwitch(locateApplication: { _ in URL(fileURLWithPath: "/fixture/Codex.app") }, openApplication: { _ in
                self.events.append("open")
            }, environment: env, home: home, progress: { self.events.append("phase:" + $0) })
        }
    }
    @MainActor static func main() async throws {
        for desktopRunning in [true, false] {
            let f = try Fixture(desktop: desktopRunning), client = f.client()
            let running = try client.preflight(); precondition(running == desktopRunning)
            try await client.stop()
            precondition(f.processes.map(\.id) == [1002], "Updater must not block auth handoff")
            f.events.append("write-auth")
            try await client.reopen(launchIfClosed: true)
            let order = f.events.filter { ["stop", "write-auth", "start", "open"].contains($0) }
            precondition(order == ["stop", "write-auth", "start", "open"])
        }
        do {
            let f = try Fixture(); f.processes.append(.init(id: 3001, parent: 1, executable: "/CLI/codex"))
            do { try await f.client().stop(); fatalError("External client must block") }
            catch CodexDesktopSwitchError.externalSession { }
            precondition(f.events.isEmpty)
        }
        do {
            let f = try Fixture(); f.refuseExit = true
            do { try await f.client().stop(); fatalError("Quit timeout must block write") }
            catch CodexDesktopSwitchError.quitTimedOut { }
            precondition(!f.events.contains("stop"))
            precondition(f.events.contains("signal:2001:9"))
        }
        do {
            let f = try Fixture(); f.stopFailure = true; let client = f.client()
            do { try await client.stop(); fatalError("Daemon failure must block write") }
            catch CodexDesktopSwitchError.daemonStopFailed { }
            try await client.reopen(launchIfClosed: false)
            precondition(f.events.suffix(2).contains("open"))
        }
        do {
            let f = try Fixture(); f.lateExternal = true
            do { try await f.client().stop(); fatalError("A racing client must block write") }
            catch CodexDesktopSwitchError.quitTimedOut { }
        }
        do {
            let f = try Fixture(); let client = f.client()
            try await client.stop(); f.startFailure = true
            do { try await client.reopen(launchIfClosed: true); fatalError("Restart failure must be reported") }
            catch CodexDesktopSwitchError.daemonStartFailed { }
            precondition(f.events.contains("open"), "Still attempt Desktop recovery")
        }
        print("Lifecycle checks passed: running/closed Desktop, retained updater, handoff order, external client, quit timeout, daemon stop/start failure, and late-client race. No real account or application touched.")
    }
}

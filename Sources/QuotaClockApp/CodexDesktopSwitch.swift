import AppKit
import Darwin

enum CodexDesktopSwitchError: Error, LocalizedError {
    case externalSession, quitDeclined, quitTimedOut, processInspection, launchFailed
    case daemonStopFailed, daemonStartFailed
    var errorDescription: String? {
        switch self {
        case .externalSession: "Close other Codex CLI or IDE sessions before switching accounts."
        case .quitDeclined: "Codex could not quit. No login was changed."
        case .quitTimedOut: "Codex is still running. No login was changed."
        case .processInspection: "Could not check running Codex sessions. No login was changed."
        case .launchFailed: "Could not reopen Codex. Open it manually."
        case .daemonStopFailed: "Could not stop the Codex background service. No login was changed."
        case .daemonStartFailed: "Could not restart the Codex background service. Open Codex manually."
        }
    }
}

/// Only the explicit account-switch action may stop Desktop. Never signal an
/// external CLI/IDE client. Identity checks protect against PID reuse.
@MainActor final class CodexDesktopSwitch {
    struct DesktopApplication { let id: Int32; let url: URL }
    struct Environment {
        var applications: @MainActor () -> [DesktopApplication]
        var processes: @MainActor () throws -> [RunningProcess]
        var signal: @MainActor (RunningProcess, Int32) throws -> Void
        var runDaemon: @MainActor (URL, String, URL) async throws -> Void
        var phaseTimeout: TimeInterval = 8
        static var live: Self {
            .init(applications: {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").compactMap {
                    guard !$0.isTerminated, let url = $0.bundleURL else { return nil }
                    return DesktopApplication(id: $0.processIdentifier, url: url)
                }
            }, processes: CodexDesktopSwitch.processes, signal: CodexDesktopSwitch.signal,
                  runDaemon: CodexDesktopSwitch.runDaemon)
        }
    }
    private var applications: [DesktopApplication] = []
    private var daemonToRestart: URL?
    private let runtime: Environment
    private let home: URL
    private let progress: (String) -> Void
    private let locateApplication: (String) -> URL?
    private let openApplication: (URL) async throws -> Void

    init(locateApplication: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
         openApplication: @escaping (URL) async throws -> Void = { url in
             let config = NSWorkspace.OpenConfiguration(); config.activates = true
             _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
         }, environment: Environment? = nil, home: URL? = nil, progress: @escaping (String) -> Void = { _ in }) {
        self.locateApplication = locateApplication; self.openApplication = openApplication
        runtime = environment ?? .live; self.progress = progress
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap {
            $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Does not read arguments, environments or credentials of other processes.
    func preflight() throws -> Bool {
        let running = runtime.applications()
        try checkForExternalClients(try runtime.processes(), desktops: running)
        return !running.isEmpty
    }
    private func checkForExternalClients(_ all: [RunningProcess], desktops: [DesktopApplication]) throws {
        let managed = Self.managedProcesses(in: all, home: home)
        // Our own children use isolated homes; the store drains its operation lease before stop().
        let roots = Set(desktops.map(\.id) + managed.map { $0.process.id } + [getpid()])
        guard !all.contains(where: { $0.isCodex && !Self.belongsToDesktop($0, in: all, roots: roots) }) else {
            throw CodexDesktopSwitchError.externalSession
        }
    }
    func stop() async throws {
        let running = runtime.applications(), before = try runtime.processes()
        try checkForExternalClients(before, desktops: running)
        applications = running
        let managed = Self.managedProcesses(in: before, home: home)
        let desktopRoots = Set(running.map(\.id))
        let desktopClients = before.filter { desktopRoots.contains($0.id) ||
            ($0.isCodex && Self.belongsToDesktop($0, in: before, roots: desktopRoots)) }

        progress("Closing Codex…")
        // Stop captured Desktop and its owned clients together, so an orphaned
        // app-server cannot consume the whole grace period. SIGTERM bypasses
        // Electron's interactive Quit dialog. After a bounded
        // grace period, only these exact Desktop processes may be force-stopped.
        for process in desktopClients { try runtime.signal(process, SIGTERM) }
        if !(try await waitForExit(desktopClients, timeout: runtime.phaseTimeout)) {
            for process in desktopClients { try runtime.signal(process, SIGTERM) }
            if !(try await waitForExit(desktopClients, timeout: min(2, runtime.phaseTimeout))) {
                for process in desktopClients { try runtime.signal(process, SIGKILL) }
                guard try await waitForExit(desktopClients, timeout: min(3, runtime.phaseTimeout)) else { throw CodexDesktopSwitchError.quitTimedOut }
            }
        }

        if let daemon = managed.first(where: { $0.role == .server }) {
            progress("Stopping Codex service…")
            daemonToRestart = URL(fileURLWithPath: daemon.process.executable)
            do { try await runtime.runDaemon(daemonToRestart!, "stop", home) }
            catch { throw CodexDesktopSwitchError.daemonStopFailed }
        }
        // `daemon stop` deliberately leaves the package updater running. It is
        // not an auth client. Trust only its separate PID/start-time record.
        let deadline = Date().addingTimeInterval(runtime.phaseTimeout)
        while true {
            let remaining = try runtime.processes()
            let updaters = Set(Self.managedProcesses(in: remaining, home: home)
                .filter { $0.role == .updater }.map { $0.process.id })
            let authClients = remaining.filter { $0.isCodex && !updaters.contains($0.id) &&
                !Self.belongsToDesktop($0, in: remaining, roots: [getpid()]) }
            if authClients.isEmpty { return }
            guard Date() < deadline else { throw CodexDesktopSwitchError.quitTimedOut }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    private func waitForExit(_ expected: [RunningProcess], timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let live = try runtime.processes()
            if !expected.contains(where: { expected in live.contains { $0.isSameProcess(as: expected) } }) { return true }
            if Date() >= deadline { return false }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    func reopen(launchIfClosed: Bool) async throws {
        var restartError: Error?
        if let daemon = daemonToRestart {
            progress("Starting Codex service…")
            do { try await runtime.runDaemon(daemon, "start", home); daemonToRestart = nil }
            catch { restartError = CodexDesktopSwitchError.daemonStartFailed }
        }
        let liveIDs = Set(runtime.applications().map(\.id))
        var urls = Set(applications.filter { !liveIDs.contains($0.id) }.map(\.url))
        if urls.isEmpty && applications.isEmpty && launchIfClosed {
            guard let url = locateApplication("com.openai.codex") else { throw CodexDesktopSwitchError.launchFailed }
            urls.insert(url)
        }
        if !urls.isEmpty { progress("Opening Codex…") }
        for url in urls {
            do { try await openApplication(url) } catch { throw CodexDesktopSwitchError.launchFailed }
        }
        if let restartError { throw restartError }
    }

    struct RunningProcess {
        let id: Int32
        let parent: Int32
        let executable: String
        var startSeconds: UInt64 = 0
        var startMicroseconds: UInt64 = 0
        var isCodex: Bool {
            let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
            return name == "codex" || name == "codex-cli" || name.hasPrefix("codex-aarch64-") || name.hasPrefix("codex-x86_64-")
        }
        func isSameProcess(as other: Self) -> Bool {
            id == other.id && startSeconds == other.startSeconds && startMicroseconds == other.startMicroseconds && executable == other.executable
        }
    }
    static func belongsToDesktop(_ process: RunningProcess, in all: [RunningProcess], roots: Set<Int32>) -> Bool {
        let parents = Dictionary(all.map { ($0.id, $0.parent) }, uniquingKeysWith: { first, _ in first })
        var id = process.id, visited = Set<Int32>()
        while id > 1 && visited.insert(id).inserted {
            if roots.contains(id) { return true }
            guard let parent = parents[id] else { return false }
            id = parent
        }
        return false
    }
    enum ManagedRole { case server, updater }
    struct ManagedProcess { let role: ManagedRole; let process: RunningProcess }
    static func managedProcesses(in all: [RunningProcess], home: URL) -> [ManagedProcess] {
        struct Record: Decodable {
            struct Identity: Decodable { let startSeconds: UInt64; let startMicroseconds: UInt64 }
            let pid: Int32; let processIdentity: Identity
        }
        return [(ManagedRole.server, "daemon.pid"), (.updater, "daemon-updater.pid")].compactMap { role, name in
            guard let data = try? Data(contentsOf: home.appendingPathComponent("app-server-daemon/" + name)), data.count < 16_384,
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  let process = all.first(where: { $0.id == record.pid }),
                  process.startSeconds == record.processIdentity.startSeconds,
                  process.startMicroseconds == record.processIdentity.startMicroseconds,
                  process.executable.hasPrefix(home.appendingPathComponent("packages/app-server-daemon/releases").path + "/"),
                  process.executable.hasSuffix("/bin/codex") else { return nil }
            return ManagedProcess(role: role, process: process)
        }
    }
    static func managedDaemonRoots(in all: [RunningProcess], home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) -> Set<Int32> {
        Set(managedProcesses(in: all, home: home).map { $0.process.id })
    }
    private static func signal(_ expected: RunningProcess, _ signal: Int32) throws {
        guard try processes().contains(where: { $0.isSameProcess(as: expected) }) else { return }
        guard kill(expected.id, signal) == 0 || errno == ESRCH else { throw CodexDesktopSwitchError.quitDeclined }
    }
    static func runDaemon(_ executable: URL, command: String, home: URL) async throws {
        let process = Process()
        process.executableURL = executable; process.arguments = ["app-server", "daemon", command]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CodexDesktopSwitchError.daemonStopFailed }
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning {
            if Date() >= deadline || Task.isCancelled {
                process.terminate()
                // Only our short-lived lifecycle command; do not leave it capable
                // of completing a delayed stop after we've restored Desktop.
                let until = Date().addingTimeInterval(1)
                while process.isRunning && Date() < until { try? await Task.sleep(nanoseconds: 50_000_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw CodexDesktopSwitchError.quitTimedOut
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard process.terminationStatus == 0 else { throw CodexDesktopSwitchError.daemonStopFailed }
    }

    static func processes() throws -> [RunningProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { throw CodexDesktopSwitchError.processInspection }
        var ids = [Int32](repeating: 0, count: Int(count) + 256)
        let bytes = Int32(ids.count * MemoryLayout<Int32>.stride)
        let received = proc_listallpids(&ids, bytes)
        guard received > 0, received < ids.count else { throw CodexDesktopSwitchError.processInspection }
        var result: [RunningProcess] = []
        for id in ids.prefix(Int(received)) where id > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(id, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { continue }
            guard info.pbi_status != UInt32(SZOMB) else { continue }
            // PROC_PIDPATHINFO_MAXSIZE is a C macro (4 * MAXPATHLEN) that Swift
            // does not import from proc_info.h.
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let read = proc_pidpath(id, &path, UInt32(path.count))
            if read <= 0 {
                guard info.pbi_uid == getuid(), kill(id, 0) == 0 else { continue }
                // A running executable can have been unlinked by an app update.
                // Kernel name remains available; retain ancestry and still detect Codex.
                let nameCapacity = MemoryLayout.size(ofValue: info.pbi_name)
                let name = withUnsafePointer(to: &info.pbi_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: nameCapacity) { String(cString: $0) }
                }
                guard !name.isEmpty else { throw CodexDesktopSwitchError.processInspection }
                result.append(RunningProcess(id: id, parent: Int32(info.pbi_ppid), executable: name))
                continue
            }
            result.append(RunningProcess(id: id, parent: Int32(info.pbi_ppid), executable: String(cString: path), startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec))
        }
        return result
    }
}

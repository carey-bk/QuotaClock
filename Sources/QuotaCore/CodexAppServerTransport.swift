import Foundation

public struct CodexAccountData: Sendable {
    public let rateLimits: Data
    public let usage: Data?
}

/// Uses Codex's own account/rateLimits/read RPC, so QuotaClock never opens Codex auth.json.
public struct CodexAppServerTransport: Sendable {
    public init() {}
    /// Resolve the launcher shipped by current ChatGPT/Codex builds before
    /// standalone installs. App bundles change layout across updates, so keep
    /// both the current codex-cli/bin path and the older Resources/codex path.
    static func executableCandidates(applications: [URL], home: URL) -> [String] {
        let bundled = applications.flatMap { app in
            [app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path,
             app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex").path,
             app.appendingPathComponent("Contents/Resources/codex").path]
        }
        return bundled + ["/usr/local/bin/codex", "/opt/homebrew/bin/codex",
                          home.appendingPathComponent(".local/bin/codex").path]
    }
    static func resolveExecutable(applications: [URL], home: URL) -> String? {
        executableCandidates(applications: applications, home: home)
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    public func readRateLimits() async throws -> Data { try await readAccountData().rateLimits }
    public func readAccountData() async throws -> CodexAccountData {
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try Self.readSynchronous(cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }
    private static func readSynchronous(cancellation: ProcessCancellation) throws -> CodexAccountData {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let apps = [URL(fileURLWithPath: "/Applications/ChatGPT.app"),
                    URL(fileURLWithPath: "/Applications/Codex.app"),
                    home.appendingPathComponent("Applications/ChatGPT.app"),
                    home.appendingPathComponent("Applications/Codex.app")]
        guard let executable = resolveExecutable(applications: apps, home: home) else { throw ProviderFetchError.unavailable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        process.standardError = Pipe() // Never retain diagnostic output, which may mention account state.
        do { try process.run() } catch { throw ProviderFetchError.unavailable }
        guard cancellation.register(process) else { throw CancellationError() }
        let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timeout.schedule(deadline: .now() + 20)
        timeout.setEventHandler { if process.isRunning { process.terminate() } }
        timeout.resume()
        defer {
            timeout.cancel()
            if process.isRunning { process.terminate() }
            input.fileHandleForWriting.closeFile()
            output.fileHandleForReading.closeFile()
        }
        let requests: [[String: Any]] = [
            ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "QuotaClock", "title": "QuotaClock", "version": "0.1.0"], "capabilities": [:]]],
            ["method": "initialized", "params": [:]],
            ["id": 2, "method": "account/rateLimits/read"]
        ]
        func send(_ request: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: request)
            input.fileHandleForWriting.write(data + Data([0x0A]))
        }
        for request in requests { try send(request) }
        var rateLimits: Data?
        var line = Data()
        while true {
            let byte = output.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty {
                if let rateLimits { return CodexAccountData(rateLimits: rateLimits, usage: nil) }
                throw cancellation.isCancelled ? CancellationError() : ProviderFetchError.timeout
            }
            if byte[0] != 0x0A {
                line.append(byte)
                if line.count > 262_144 { throw ProviderFetchError.invalidResponse }
                continue
            }
            defer { line.removeAll(keepingCapacity: true) }
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = json["id"] as? Int, id == 2 || id == 3 else { continue }
            if id == 3 {
                guard let rateLimits else { continue }
                return CodexAccountData(rateLimits: rateLimits, usage: json["error"] == nil ? line : nil)
            }
            if let error = json["error"] as? [String: Any] {
                let message = (error["message"] as? String ?? "").lowercased()
                if message.contains("authentication") || message.contains("auth") { throw ProviderFetchError.authenticationRequired }
                throw ProviderFetchError.unavailable
            }
            rateLimits = line
            try send(["id": 3, "method": "account/usage/read"])
            // Usage is optional. Do not delay a valid quota for a long-running
            // or unsupported usage RPC.
            timeout.schedule(deadline: .now() + 5)
        }
    }
}

final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func register(_ process: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled {
            if process.isRunning { process.terminate() }
            return false
        }
        self.process = process
        return true
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}

import Foundation
import Darwin

public struct CodexSignInPrompt: Sendable {
    public let url: URL
    let loginID: String
    init(response: [String: Any]) throws {
        guard let id = response["loginId"] as? String, !id.isEmpty, id.count < 512,
              let raw = response["authUrl"] as? String, raw.count <= 16_384,
              !raw.contains(where: { $0.isWhitespace }), let url = URL(string: raw),
              url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              ["auth.openai.com", "chatgpt.com"].contains(url.host?.lowercased() ?? "") else {
            throw AccountError.invalidLoginURL
        }
        self.url = url; loginID = id
    }
}

/// The only RPCs this client issues are initialization, authentication and account reads.
/// Never points a child at the active CODEX_HOME or passes secrets via argv/environment.
struct IsolatedCodexRPC: Sendable {
    var executable: String?
    var timeout: TimeInterval = 25
    enum Operation: Sendable {
        case read(CodexCredential?, usage: Bool = true)
        case login(@Sendable (CodexSignInPrompt) -> Void)
    }
    func run(home: URL, operation: Operation) async throws -> CodexAccountData? {
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try self.runSync(home: home, operation: operation, cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
    static func environment(home: URL, inherited: [String: String]) -> [String: String] {
        let allowed = ["PATH", "LANG", "LC_ALL", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                       "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR"]
        var result = inherited.filter { allowed.contains($0.key) }
        result["CODEX_HOME"] = home.path
        // No global config, projects, sessions, plugins, API keys or auth overrides are inherited.
        result["HOME"] = home.path
        return result
    }
    private func runSync(home: URL, operation: Operation, cancellation: ProcessCancellation) throws -> CodexAccountData? {
        let user = FileManager.default.homeDirectoryForCurrentUser
        let apps = ["/Applications/ChatGPT.app", "/Applications/Codex.app", user.appendingPathComponent("Applications/ChatGPT.app").path,
                    user.appendingPathComponent("Applications/Codex.app").path].map { URL(fileURLWithPath: $0) }
        guard let executable = executable ?? CodexAppServerTransport.resolveExecutable(applications: apps, home: user) else {
            throw ProviderFetchError.unavailable
        }
        if cancellation.isCancelled { throw CancellationError() }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = CodexAppServerTransport.accountArguments(isolated: true)
        process.environment = Self.environment(home: home, inherited: ProcessInfo.processInfo.environment)
        process.currentDirectoryURL = home
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        // F_NOSIGPIPE prevents a crashed peer from terminating the main app during a write.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch { throw ProviderFetchError.unavailable }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let until = Date().addingTimeInterval(1)
            while process.isRunning && Date() < until { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit() // Capture auth only after the sole writer has exited.
            try? FileManager.default.removeItem(at: home.appendingPathComponent("writer.pid"))
            try? output.fileHandleForReading.close()
        }
        try Data(String(process.processIdentifier).utf8).write(to: home.appendingPathComponent("writer.pid"), options: .atomic)
        guard cancellation.register(process) else { throw CancellationError() }
        // A quota refresh has one budget for the whole conversation. Giving each
        // RPC a fresh budget could leave Refresh disabled across multiple polls.
        let readDeadline: Date?
        switch operation {
        case .read: readDeadline = Date().addingTimeInterval(timeout)
        case .login: readDeadline = nil
        }
        var pending = Data()
        func send(_ value: [String: Any]) throws {
            do { try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10])) }
            catch { throw ProviderFetchError.unavailable }
        }
        func next(until deadline: Date) throws -> (Data, [String: Any]) {
            while Date() < deadline {
                if cancellation.isCancelled { throw CancellationError() }
                if let newline = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: newline); pending.removeSubrange(...newline)
                    guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    return (Data(line), json)
                }
                guard pending.count <= 1_048_576 else { throw ProviderFetchError.invalidResponse }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, 100)
                if ready < 0 { if errno == EINTR { continue }; throw ProviderFetchError.unavailable }
                if ready > 0 {
                    var bytes = [UInt8](repeating: 0, count: 8192)
                    let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                    guard count > 0 else { throw cancellation.isCancelled ? CancellationError() : ProviderFetchError.unavailable }
                    pending.append(contentsOf: bytes.prefix(count))
                }
            }
            throw ProviderFetchError.timeout
        }
        var nextID = 0
        func request(_ method: String, _ params: [String: Any]? = nil, wait: TimeInterval? = nil) throws -> (Data, [String: Any]) {
            nextID += 1; let id = nextID
            var payload: [String: Any] = ["id": id, "method": method]
            if let params { payload["params"] = params }
            try send(payload)
            let deadline = min(Date().addingTimeInterval(wait ?? timeout), readDeadline ?? .distantFuture)
            while true {
                let (data, json) = try next(until: deadline)
                if let serverMethod = json["method"] as? String, let serverID = json["id"] {
                    // A linked login never refreshes the real session; fail explicitly instead.
                    try send(["id": serverID, "error": ["code": -32000, "message": "Authentication required"]])
                    if serverMethod == "account/chatgptAuthTokens/refresh" { throw ProviderFetchError.authenticationRequired }
                    continue
                }
                guard json["id"] as? Int == id else { continue }
                if let error = json["error"] as? [String: Any] {
                    let message = (error["message"] as? String ?? "").lowercased()
                    if ["auth", "401", "expired", "revoked", "refresh_token", "invalid_grant"].contains(where: message.contains) {
                        throw ProviderFetchError.authenticationRequired
                    }
                    if message.contains("429") { throw ProviderFetchError.rateLimited }
                    throw ProviderFetchError.unavailable // Never expose provider error text or secrets.
                }
                guard let result = json["result"] as? [String: Any] else { throw ProviderFetchError.invalidResponse }
                return (data, result)
            }
        }
        _ = try request("initialize", ["clientInfo": ["name": "QuotaClock", "version": "0.10.0"],
                                       "capabilities": ["experimentalApi": true]])
        try send(["method": "initialized"])
        switch operation {
        case .login(let show):
            let (_, result) = try request("account/login/start", ["type": "chatgpt"])
            let prompt = try CodexSignInPrompt(response: result)
            show(prompt)
            let deadline = Date().addingTimeInterval(600)
            while true {
                let (_, message) = try next(until: deadline)
                guard message["method"] as? String == "account/login/completed",
                      let params = message["params"] as? [String: Any], params["loginId"] as? String == prompt.loginID else { continue }
                guard params["success"] as? Bool == true else { throw ProviderFetchError.authenticationRequired }
                return nil
            }
        case .read(let linked, let includeUsage):
            if let linked { _ = try request("account/login/start", linked.externalLogin) }
            // For owned credentials Codex checks token expiry on account/read. Never force a rotation each minute.
            _ = try request("account/read", ["refreshToken": false])
            let limits: Data
            do { limits = try request("account/rateLimits/read").0 }
            catch ProviderFetchError.authenticationRequired where linked == nil {
                // Rotate owned credentials once on an authorization failure, never a linked session.
                _ = try request("account/read", ["refreshToken": true])
                limits = try request("account/rateLimits/read").0
            }
            let usage = includeUsage ? (try? request("account/usage/read", wait: 5).0) : nil
            return CodexAccountData(rateLimits: limits, usage: usage)
        }
    }
}

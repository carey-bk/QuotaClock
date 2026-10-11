import Foundation
import Darwin

public protocol ProviderEngineTransport: Sendable {
    func usage(provider: String) async throws -> Data
}

public struct ProviderEngineAdapter: ProductAdapter {
    public let definition: ProviderEngineDefinition
    public var descriptor: ProductDescriptor { definition.descriptor }
    public var minimumRefreshInterval: TimeInterval { 300 }
    private let transport: any ProviderEngineTransport
    public init(definition: ProviderEngineDefinition, transport: any ProviderEngineTransport = BundledProviderEngine()) {
        self.definition = definition; self.transport = transport
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        try Self.parse(await transport.usage(provider: definition.id), definition: definition, at: date)
    }
    public static func parse(_ data: Data, definition: ProviderEngineDefinition, at date: Date) throws -> ProductQuota {
        guard data.count <= 2_097_152,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.count == 1,
              let row = rows.first, row["provider"] as? String == definition.id else { throw ProviderFetchError.invalidResponse }
        if let error = row["error"] as? [String: Any] {
            if (error["code"] as? Int) == 4 { throw ProviderFetchError.timeout }
            throw ProviderFetchError.unavailable
        }
        let usage = row["usage"] as? [String: Any] ?? [:]
        let updated = try MeterJSON.date(usage["updatedAt"]) ?? date
        let labels = row["rateWindowLabels"] as? [String: String] ?? [:]
        var meters: [Meter] = []
        func window(_ raw: Any?, id: String, label: String) throws {
            guard let raw, !(raw is NSNull) else { return }
            guard let w = raw as? [String: Any] else { throw ProviderFetchError.invalidResponse }
            if w["isSyntheticPlaceholder"] as? Bool == true { return }
            let used = try MeterJSON.number(w["usedPercent"])
            guard used >= 0 else { throw ProviderFetchError.invalidResponse }
            let minutes = try w["windowMinutes"].flatMap { $0 is NSNull ? nil : try MeterJSON.number($0) }
            meters.append(Meter(id: id, displayName: label, kind: .percentageQuota, value: max(0, 100 - used),
                resetAt: try MeterJSON.date(w["resetsAt"]), windowDuration: minutes.map { NSDecimalNumber(decimal: $0).doubleValue * 60 },
                updatedAt: updated, reliability: .communityVerified))
        }
        for key in ["primary", "secondary", "tertiary"] { try window(usage[key], id: key, label: labels[key] ?? key.capitalized) }
        if let extras = usage["extraRateWindows"] as? [[String: Any]] {
            for extra in extras where extra["usageKnown"] as? Bool != false {
                guard let id = extra["id"] as? String, let title = extra["title"] as? String else { throw ProviderFetchError.invalidResponse }
                try window(extra["window"], id: "extra." + id, label: title)
            }
        }
        // Only typed numeric detail progress is mapped. Never parse display strings as balances or quota.
        if let sections = usage["details"] as? [[String: Any]] {
            guard sections.count <= 8 else { throw ProviderFetchError.invalidResponse }
            for (sectionIndex, section) in sections.enumerated() {
                let rows = section["rows"] as? [[String: Any]] ?? []
                guard rows.count <= 24 else { throw ProviderFetchError.invalidResponse }
                for (index, detail) in rows.enumerated() {
                    guard let progress = detail["progress"] as? [String: Any],
                          let label = detail["label"] as? String, !label.isEmpty, label.count <= 120 else { continue }
                    let used = try MeterJSON.number(progress["used"]), total = try MeterJSON.number(progress["total"])
                    guard used >= 0, total > 0 else { throw ProviderFetchError.invalidResponse }
                    meters.append(Meter(id: "detail.\(sectionIndex).\(index)", displayName: label, kind: .percentageQuota,
                        value: max(0, (total - used) / total * 100), updatedAt: updated, reliability: .communityVerified))
                }
            }
        }
        if let cost = usage["providerCost"] as? [String: Any], let currency = cost["currencyCode"] as? String {
            let costDate = try MeterJSON.date(cost["updatedAt"]) ?? updated
            if let balance = cost["balance"], !(balance is NSNull) {
                meters.append(Meter(id: "balance", displayName: "Balance", kind: .balance, value: try MeterJSON.number(balance), currency: currency, updatedAt: costDate, reliability: .communityVerified))
            }
            if let used = cost["used"], !(used is NSNull) {
                meters.append(Meter(id: "spend", displayName: "Spent", kind: .spend, value: try MeterJSON.number(used), currency: currency,
                    resetAt: try MeterJSON.date(cost["resetsAt"]), updatedAt: costDate, reliability: .communityVerified))
            }
        }
        if let credits = row["credits"] as? [String: Any], credits["balanceReadSucceeded"] as? Bool != false,
           let remaining = credits["remaining"], !(remaining is NSNull) {
            meters.append(Meter(id: "credits", displayName: "Credits", kind: .credits, value: try MeterJSON.number(remaining),
                updatedAt: try MeterJSON.date(credits["updatedAt"]) ?? updated, reliability: .communityVerified))
        }
        guard !meters.isEmpty, Set(meters.map(\.id)).count == meters.count else { throw ProviderFetchError.invalidResponse }
        let identity = usage["identity"] as? [String: Any]
        var product = ProductQuota(id: definition.productID, providerID: definition.providerID, displayName: definition.name,
            meters: meters, at: updated, planName: identity?["loginMethod"] as? String ?? usage["loginMethod"] as? String)
        if let reset = row["resetCredits"] as? [String: Any], let raw = reset["available"] {
            let value = try MeterJSON.number(raw)
            guard let count = Int(exactly: NSDecimalNumber(decimal: value).doubleValue), count >= 0 else { throw ProviderFetchError.invalidResponse }
            product.bankResetCount = count
        }
        // Account emails, diagnostics, cookies, reset IDs and raw detail strings never enter the display snapshot.
        return try product.validated()
    }
}

private actor ProviderEngineGate {
    static let shared = ProviderEngineGate()
    private var running = 0
    func acquire() async throws {
        while running >= 2 { try await Task.sleep(nanoseconds: 100_000_000) }
        try Task.checkCancellation(); running += 1
    }
    func release() { running -= 1 }
}

public struct BundledProviderEngine: ProviderEngineTransport {
    public init() {}
    public func usage(provider: String) async throws -> Data {
        guard ProviderEngineCatalog.all.contains(where: { $0.id == provider }) else { throw ProviderFetchError.invalidResponse }
        try await ProviderEngineGate.shared.acquire()
        do {
            let config = try ProviderEngineConfiguration.ensure(provider)
            let cancellation = ProcessCancellation()
            let result = try await withTaskCancellationHandler(operation: {
                try await Task.detached(priority: .utility) { try Self.run(provider: provider, config: config, cancellation: cancellation) }.value
            }, onCancel: { cancellation.cancel() })
            await ProviderEngineGate.shared.release()
            return result
        } catch { await ProviderEngineGate.shared.release(); throw error }
    }
    static func run(provider: String, config: URL, cancellation: ProcessCancellation,
                    executableURL: URL? = nil, timeout: TimeInterval = 25) throws -> Data {
        guard let executable = executableURL ?? Bundle.main.url(forAuxiliaryExecutable: "QuotaClockProviderEngine"),
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw ProviderFetchError.unavailable }
        let output = Pipe()
        let handle = output.fileHandleForReading
        let fd = handle.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else { throw ProviderFetchError.unavailable }
        defer { try? handle.close() }
        let process = Process(); process.executableURL = executable
        process.arguments = ["usage", "--provider", provider, "--format", "json", "--timeout", "20"]
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "NO_COLOR": "1", "CODEXBAR_CONFIG": config.path]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        try? output.fileHandleForWriting.close()
        _ = cancellation.register(process)
        let deadline = Date().addingTimeInterval(timeout)
        var oversized = false
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        while !cancellation.isCancelled && Date() < deadline {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 {
                guard data.count + count <= 2_097_152 else { oversized = true; break }
                data.append(contentsOf: bytes.prefix(count))
            } else if count == 0 { break }
            else if errno == EAGAIN || errno == EWOULDBLOCK {
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.01)
            } else if errno != EINTR { oversized = true; break }
        }
        while process.isRunning && !oversized && !cancellation.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(1)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            if cancellation.isCancelled { throw CancellationError() }
            throw oversized ? ProviderFetchError.invalidResponse : ProviderFetchError.timeout
        }
        if cancellation.isCancelled { throw CancellationError() }
        if oversized { throw ProviderFetchError.invalidResponse }
        if process.terminationStatus == 4 { throw ProviderFetchError.timeout }
        // Never publish successful-looking stdout after a failed process.
        guard process.terminationReason == .exit, process.terminationStatus == 0, !data.isEmpty else { throw ProviderFetchError.unavailable }
        return data
    }
}

import Foundation

public protocol ProductCLITransport: Sendable {
    func usage(product: String, profile: String) async throws -> Data
}
public struct BailianCLITransport: ProductCLITransport {
    public init() {}
    public func usage(product: String, profile: String) async throws -> Data {
        guard ["coding-plan", "token-plan"].contains(product),
              profile.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else { throw ProviderFetchError.invalidResponse }
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler {
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try Self.run(product: product, profile: profile, cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
            return data
        } onCancel: { cancellation.cancel() }
    }
    private static func run(product: String, profile: String, cancellation: ProcessCancellation) throws -> Data {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["/opt/homebrew/bin/bl", "/usr/local/bin/bl", home.appendingPathComponent(".local/bin/bl").path]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw ProviderFetchError.unavailable }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
        // Read-only, explicit profile; never run login, create-key or any inference command.
        process.arguments = ["usage", product, "--output", "json", "--config", profile]
        process.environment = ["HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "NO_COLOR": "1"]
        let output = Pipe(); process.standardOutput = output
        process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        guard cancellation.register(process) else { throw CancellationError() }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 20)
        timer.setEventHandler { if process.isRunning { process.terminate() } }
        timer.resume()
        defer { timer.cancel(); if process.isRunning { process.terminate() }; output.fileHandleForReading.closeFile() }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.readData(ofLength: 4096)
            if chunk.isEmpty { break }
            data.append(chunk)
            guard data.count <= 1_048_576 else { throw ProviderFetchError.invalidResponse }
        }
        process.waitUntilExit()
        if cancellation.isCancelled { throw CancellationError() }
        if process.terminationReason == .uncaughtSignal { throw ProviderFetchError.timeout }
        switch process.terminationStatus {
        case 0: break
        case 3: throw ProviderFetchError.authenticationRequired
        case 4: throw ProviderFetchError.rateLimited
        case 5: throw ProviderFetchError.timeout
        default: throw ProviderFetchError.unavailable
        }
        return data
    }
}
public struct BailianProvider: ProductAdapter {
    public let descriptor: ProductDescriptor
    private let product: String
    private let transport: any ProductCLITransport
    private let profile: @Sendable () -> String
    public init(product: String, transport: any ProductCLITransport = BailianCLITransport(),
                profile: @escaping @Sendable () -> String = { "default" }) {
        self.product = product; self.descriptor = ProviderCatalog.product("bailian.\(product)")
        self.transport = transport; self.profile = profile
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        try Self.parse(await transport.usage(product: product, profile: profile()), product: product, at: date)
    }
    public static func parse(_ data: Data, product: String, at date: Date) throws -> ProductQuota {
        let root = try MeterJSON.object(data)
        var meters: [Meter] = []
        if product == "coding-plan" {
            for (key, label, duration) in [("per5Hour", "5-hour", 18000.0), ("perWeek", "Weekly", 604800.0), ("perBillMonth", "Monthly", 0.0)] {
                guard let value = root[key] else { continue }
                guard let row = value as? [String: Any] else { throw ProviderFetchError.invalidResponse }
                if row.isEmpty { continue }
                let used = try MeterJSON.number(row["usedQuota"]), total = try MeterJSON.number(row["totalQuota"])
                let remaining = try MeterJSON.percent(used: used, total: total)
                meters.append(Meter(id: key, displayName: label, kind: .percentageQuota, value: remaining, total: total,
                    remaining: total - used, unit: "requests", resetAt: try MeterJSON.date(row["resetTime"], milliseconds: true),
                    windowDuration: duration == 0 ? nil : duration, updatedAt: date, reliability: .officialCLI))
            }
        } else if product == "token-plan" {
            for (key, label, duration) in [("per5Hour", "5-hour", 18000.0), ("per1Week", "Weekly", 604800.0)] {
                guard let raw = root[key + "Percentage"] else { continue }
                let used = try MeterJSON.number(raw)
                meters.append(Meter(id: key, displayName: label, kind: .percentageQuota,
                    value: try MeterJSON.percent(used: used, total: 1),
                    resetAt: try MeterJSON.date(root[key + "ResetTime"], milliseconds: true), windowDuration: duration,
                    updatedAt: date, reliability: .officialCLI))
            }
        } else { throw ProviderFetchError.unavailable }
        guard !meters.isEmpty else { throw ProviderFetchError.unavailable }
        let definition = ProviderCatalog.product("bailian.\(product)")
        return try ProductQuota(id: definition.id, providerID: "bailian", displayName: definition.displayName,
            meters: meters, at: date, planName: root["instanceType"] as? String).validated()
    }
}

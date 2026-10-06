import Foundation

/// A price is usable only for its exact model and bounded effective interval. No bundled permanent rates.
public struct UsagePricing: Codable, Equatable, Sendable {
    public var model: String
    public var currency: String
    public var inputPerMillion: Decimal
    public var cachedPerMillion: Decimal
    public var outputPerMillion: Decimal
    public var version: String
    public var sourceURL: URL
    public var verifiedAt: Date
    public var validUntil: Date
    public init(model: String, currency: String, inputPerMillion: Decimal, cachedPerMillion: Decimal,
                outputPerMillion: Decimal, version: String, sourceURL: URL, verifiedAt: Date, validUntil: Date) {
        self.model = model; self.currency = currency; self.inputPerMillion = inputPerMillion
        self.cachedPerMillion = cachedPerMillion; self.outputPerMillion = outputPerMillion
        self.version = version; self.sourceURL = sourceURL; self.verifiedAt = verifiedAt; self.validUntil = validUntil
    }
    public func estimate(_ usage: ResponsesTokenUsage, model: String, at date: Date) -> Decimal? {
        guard self.model == model, ["CNY", "USD"].contains(currency), !version.isEmpty,
              sourceURL.scheme == "https", sourceURL.user == nil, sourceURL.password == nil,
              sourceURL.query == nil, sourceURL.fragment == nil,
              verifiedAt <= date, date < validUntil, validUntil.timeIntervalSince(verifiedAt) <= 31 * 86400,
              [inputPerMillion, cachedPerMillion, outputPerMillion].allSatisfy({ !$0.isNaN && $0 >= 0 }),
              (try? usage.validated()) != nil,
              usage.cachedTokens != nil || inputPerMillion == cachedPerMillion else { return nil }
        let cached = usage.cachedTokens ?? 0
        return (Decimal(usage.inputTokens - cached) * inputPerMillion + Decimal(cached) * cachedPerMillion +
                Decimal(usage.outputTokens) * outputPerMillion) / 1_000_000
    }
}

/// Allowlist persisted record: content, headers, keys and endpoint configuration cannot enter this type.
public struct ObservedUsageRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let providerID: String
    public let productID: String
    public let model: String
    public let usage: ResponsesTokenUsage
    public let estimatedCost: Decimal?
    public let pricing: UsagePricing?
    public init(id: UUID = UUID(), timestamp: Date, providerID: String, productID: String, model: String,
                usage: ResponsesTokenUsage, pricing: UsagePricing? = nil) {
        self.id = id; self.timestamp = timestamp; self.providerID = providerID; self.productID = productID
        self.model = model; self.usage = usage
        let cost = pricing?.estimate(usage, model: model, at: timestamp)
        self.estimatedCost = cost; self.pricing = cost == nil ? nil : pricing
    }
    func validated() throws -> Self {
        guard !providerID.isEmpty, !productID.isEmpty, !model.isEmpty, model.count <= 200,
              timestamp.timeIntervalSince1970.isFinite,
              estimatedCost == pricing?.estimate(usage, model: model, at: timestamp) else { throw ResponsesUsageError.storage }
        _ = try usage.validated()
        return self
    }
}

public enum PrivateUsageFiles {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuotaClock/LocalUsage", isDirectory: true)
    }
    static func write<T: Encodable>(_ value: T, to url: URL, maximumBytes: Int = 32 * 1_048_576) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw ResponsesUsageError.storage }
        // Atomic replacement inherits private directory protection; restrict final inode as well.
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public struct GenericAPIRegistry: Sendable {
    public let url: URL
    public init(url: URL = PrivateUsageFiles.directory.appendingPathComponent("providers.json")) { self.url = url }
    public func read() throws -> [GenericAPIConfiguration] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw ResponsesUsageError.storage }
        let configs = try JSONDecoder().decode([GenericAPIConfiguration].self, from: data)
        guard Set(configs.map(\.id)).count == configs.count, configs.count <= 100 else { throw ResponsesUsageError.storage }
        for config in configs { _ = try config.endpoint() }
        return configs
    }
    public func write(_ configs: [GenericAPIConfiguration]) throws {
        guard configs.count <= 100, Set(configs.map(\.id)).count == configs.count else { throw ResponsesUsageError.storage }
        for config in configs { _ = try config.endpoint() }
        try PrivateUsageFiles.write(configs, to: url, maximumBytes: 1_048_576)
    }
}

public actor ObservedUsageStore {
    private let url: URL
    public init(url: URL = PrivateUsageFiles.directory.appendingPathComponent("requests.json")) { self.url = url }
    private func records() throws -> [ObservedUsageRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1_048_576 else { throw ResponsesUsageError.storage }
        let records = try JSONDecoder().decode([ObservedUsageRecord].self, from: data)
        guard records.count <= 100_000, Set(records.map(\.id)).count == records.count else { throw ResponsesUsageError.storage }
        return try records.map { try $0.validated() }
    }
    public func append(_ record: ObservedUsageRecord) throws {
        _ = try record.validated()
        var all = try records()
        guard !all.contains(where: { $0.id == record.id }) else { return }
        guard all.count < 100_000 else { throw ResponsesUsageError.storage }
        all.append(record)
        try PrivateUsageFiles.write(all, to: url)
    }
    public func remove(productID: String) throws {
        try PrivateUsageFiles.write(records().filter { $0.productID != productID }, to: url)
    }
    public func meters(providerID: String, productID: String, now: Date, calendar: Calendar = .current) throws -> [Meter] {
        let all = try records().filter { $0.providerID == providerID && $0.productID == productID && $0.timestamp <= now }
        let windows: [(String, String, Calendar.Component)] = [
            ("day", "Observed Today", .day), ("week", "Observed This Week", .weekOfYear), ("month", "Observed This Month", .month)]
        var result: [Meter] = []
        for (id, name, component) in windows {
            guard let interval = calendar.dateInterval(of: component, for: now) else { continue }
            let rows = all.filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
            let tokens = rows.reduce(Decimal.zero) { $0 + Decimal($1.usage.totalTokens) }
            result.append(Meter(id: "observed.\(id).tokens", displayName: name, kind: .usage, value: tokens,
                unit: "tokens", updatedAt: now, reliability: .officialLocalState))
            // A partially priced window cannot masquerade as the total cost; retain currency separation.
            if !rows.isEmpty, rows.allSatisfy({ $0.estimatedCost != nil }),
               let currency = rows.first?.pricing?.currency, rows.allSatisfy({ $0.pricing?.currency == currency }) {
                let cost = rows.reduce(Decimal.zero) { $0 + ($1.estimatedCost ?? 0) }
                result.append(Meter(id: "observed.\(id).cost", displayName: "Estimated Cost · " + name, kind: .spend,
                    value: cost, currency: currency, updatedAt: now, reliability: .officialLocalState))
            }
        }
        return result
    }
}

/// Local refresh aggregates observed requests; it never generates paid model traffic.
public struct GenericAPIProduct: ProductAdapter {
    public let configuration: GenericAPIConfiguration
    public let store: ObservedUsageStore
    public var descriptor: ProductDescriptor { configuration.descriptor }
    public init(configuration: GenericAPIConfiguration, store: ObservedUsageStore) {
        self.configuration = configuration; self.store = store
    }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        let meters = try await store.meters(providerID: descriptor.providerID, productID: descriptor.id, now: date)
        return ProductQuota(id: descriptor.id, providerID: descriptor.providerID, displayName: descriptor.displayName,
            meters: meters, at: date, defaultMeterID: "observed.day.tokens")
    }
}

/// Composition boundary for a verified entitlement adapter plus content-free observed usage.
/// Entitlement failure still propagates; usage never invents account health or zero quota.
public struct UsageEnrichedProductAdapter: ProductAdapter {
    private let entitlement: any ProductAdapter
    private let store: ObservedUsageStore
    public var descriptor: ProductDescriptor { entitlement.descriptor }
    public init(entitlement: any ProductAdapter, store: ObservedUsageStore) { self.entitlement = entitlement; self.store = store }
    public func fetchProduct(at date: Date) async throws -> ProductQuota {
        var product = try await entitlement.fetchProduct(at: date)
        product.meters += try await store.meters(providerID: descriptor.providerID, productID: descriptor.id, now: date)
        return try product.validated()
    }
}

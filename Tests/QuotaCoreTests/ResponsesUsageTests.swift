import XCTest
@testable import QuotaCore

final class ResponsesUsageTests: XCTestCase {
    private let config = GenericAPIConfiguration(name: "Test API", baseURL: "https://example.com/v1", model: "fixture-model")
    private let now = Date(timeIntervalSince1970: 1_790_611_200)
    private func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/Responses/completed.json"))
    }
    private func path() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("requests.json")
    }
    private func record(_ usage: ResponsesTokenUsage, at: Date? = nil, pricing: UsagePricing? = nil) -> ObservedUsageRecord {
        .init(timestamp: at ?? now, providerID: config.providerID, productID: config.productID, model: config.model, usage: usage, pricing: pricing)
    }
    func testOfficialUsageIncludesCachedAndReasoningWithoutDoubleCounting() throws {
        let usage = try ResponsesTokenUsage.parse(fixture())
        XCTAssertEqual(usage.totalTokens, 130); XCTAssertEqual(usage.cachedTokens, 40); XCTAssertEqual(usage.reasoningTokens, 10)
    }
    func testOptionalMissingNullAndIncompleteAccepted() throws {
        for status in ["completed", "incomplete"] {
            let data = Data("{\"object\":\"response\",\"status\":\"\(status)\",\"usage\":{\"input_tokens\":2,\"output_tokens\":3,\"total_tokens\":5,\"input_tokens_details\":null}}".utf8)
            let usage = try ResponsesTokenUsage.parse(data)
            XCTAssertEqual(usage.totalTokens, 5); XCTAssertNil(usage.cachedTokens); XCTAssertNil(usage.reasoningTokens)
        }
    }
    func testMalformedUsageNeverBecomesZero() throws {
        for usage in ["null", "{}", #"{"input_tokens":true,"output_tokens":3,"total_tokens":4}"#,
                      #"{"input_tokens":-1,"output_tokens":3,"total_tokens":2}"#,
                      #"{"input_tokens":1.5,"output_tokens":3,"total_tokens":4.5}"#,
                      #"{"input_tokens":1,"output_tokens":3,"total_tokens":99}"#,
                      #"{"input_tokens":1,"output_tokens":3,"total_tokens":4,"input_tokens_details":{"cached_tokens":2}}"#,
                      #"{"input_tokens":1,"output_tokens":3,"total_tokens":4,"output_tokens_details":{"reasoning_tokens":4}}"#,
                      #"{"input_tokens":1e99,"output_tokens":3,"total_tokens":1e99}"#] {
            XCTAssertThrowsError(try ResponsesTokenUsage.parse(Data("{\"object\":\"response\",\"status\":\"completed\",\"usage\":\(usage)}".utf8)))
        }
        XCTAssertThrowsError(try ResponsesTokenUsage.parse(Data(#"{"object":"chat.completion","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#.utf8)))
        XCTAssertThrowsError(try ResponsesTokenUsage.parse(Data(#"{"object":"response","status":"failed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#.utf8)))
    }
    func testSafeConfigurationAndExplicitProtocol() throws {
        XCTAssertEqual(try config.endpoint().absoluteString, "https://example.com/v1/responses")
        for url in ["http://example.com/v1", "https://user:key@example.com/v1", "https://example.com/v1?api_key=secret", "https://example.com/v1#token", "file:///tmp/endpoint"] {
            var invalid = config; invalid.baseURL = url
            XCTAssertThrowsError(try invalid.endpoint())
        }
        var explicit = config; explicit.baseURL = "https://example.com/v1/responses/"
        XCTAssertEqual(try explicit.endpoint().path, "/v1/responses")
        explicit.apiProtocol = .chatCompletions
        XCTAssertThrowsError(try explicit.endpoint())
    }
    func testProbeRequestAndErrorMatrix() async throws {
        let client = ProbeClient(data: try fixture(), status: 200)
        let parsed = try await ResponsesUsageTransport(client: client).validate(config, credential: "test-only-key")
        XCTAssertEqual(parsed.totalTokens, 130)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["input"] as? String, "Reply OK.")
        XCTAssertEqual(body["store"] as? Bool, false); XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 16)
        XCTAssertEqual(request.httpMethod, "POST")
        for (status, expected) in [(401, ResponsesUsageError.authentication), (403, .authentication), (429, .rateLimited), (302, .transport), (500, .transport)] {
            let failure = ProbeClient(data: Data("SERVER_SECRET".utf8), status: status)
            do { _ = try await ResponsesUsageTransport(client: failure).validate(config, credential: "test-key"); XCTFail() }
            catch { XCTAssertEqual(error as? ResponsesUsageError, expected); XCTAssertFalse(error.localizedDescription.contains("SERVER_SECRET")) }
            let count = await failure.requests.count; XCTAssertEqual(count, 1, "No protocol fallback or automatic paid retry")
        }
        do { _ = try await ResponsesUsageTransport(client: TimeoutClient()).validate(config, credential: "test-key"); XCTFail() }
        catch { XCTAssertEqual(error as? ResponsesUsageError, .timeout) }
    }
    func testCalendarAggregationBoundariesDeduplicationAndPrivacy() async throws {
        let file = path(), usage = try ResponsesTokenUsage.parse(fixture())
        let store = ObservedUsageStore(url: file)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!; calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let current = record(usage)
        try await store.append(current); try await store.append(current)
        try await store.append(record(usage, at: today.addingTimeInterval(-1)))
        try await store.append(record(usage, at: now.addingTimeInterval(1))) // future rows excluded
        let meters = try await store.meters(providerID: config.providerID, productID: config.productID, now: now, calendar: calendar)
        XCTAssertEqual(meters.first?.value, 130)
        XCTAssertTrue(meters.allSatisfy { $0.kind == .usage && $0.resetAt == nil })
        XCTAssertFalse(meters.contains { $0.kind == .spend })
        let restored = ObservedUsageStore(url: file)
        let again = try await restored.meters(providerID: config.providerID, productID: config.productID, now: now, calendar: calendar)
        XCTAssertEqual(again, meters)
        let raw = try String(contentsOf: file, encoding: .utf8)
        for forbidden in ["CONTENT_MUST_NOT_PERSIST", "Authorization", "test-only-key", "prompt", "output_text", "baseURL"] { XCTAssertFalse(raw.contains(forbidden)) }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testDayWeekMonthIsolationAndDST() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!; calendar.firstWeekday = 2
        let date = ISO8601DateFormatter().date(from: "2026-11-01T23:00:00Z")!
        let usage = try ResponsesTokenUsage.parse(fixture()), store = ObservedUsageStore(url: path())
        let day = calendar.dateInterval(of: .day, for: date)!
        XCTAssertEqual(day.duration, 25 * 3600)
        for timestamp in [day.start, day.start.addingTimeInterval(-1)] { try await store.append(record(usage, at: timestamp)) }
        try await store.append(.init(timestamp: date, providerID: "another", productID: config.productID, model: config.model, usage: usage))
        let meters = try await store.meters(providerID: config.providerID, productID: config.productID, now: date, calendar: calendar)
        XCTAssertEqual(meters.map(\.value), [130, 260, 130])
    }
    func testPricingFreshnessUnknownCacheAndPartialCost() async throws {
        let usage = try ResponsesTokenUsage.parse(fixture())
        let price = UsagePricing(model: config.model, currency: "CNY", inputPerMillion: 2, cachedPerMillion: 1,
            outputPerMillion: 4, version: "fixture-2026-09", sourceURL: URL(string: "https://example.com/pricing")!,
            verifiedAt: now.addingTimeInterval(-86400), validUntil: now.addingTimeInterval(86400))
        XCTAssertEqual(price.estimate(usage, model: config.model, at: now), Decimal(string: "0.00028"))
        XCTAssertNil(price.estimate(usage, model: "different-model", at: now))
        XCTAssertNil(price.estimate(usage, model: config.model, at: now.addingTimeInterval(86400)))
        let unknownCache = ResponsesTokenUsage(inputTokens: 100, outputTokens: 30, totalTokens: 130, cachedTokens: nil, reasoningTokens: nil)
        XCTAssertNil(price.estimate(unknownCache, model: config.model, at: now))
        let store = ObservedUsageStore(url: path())
        try await store.append(record(usage, pricing: price))
        let priced = try await store.meters(providerID: config.providerID, productID: config.productID, now: now)
        XCTAssertEqual(priced.filter { $0.kind == .spend }.count, 3)
        try await store.append(record(usage))
        let partial = try await store.meters(providerID: config.providerID, productID: config.productID, now: now)
        XCTAssertFalse(partial.contains { $0.kind == .spend })
    }
    func testCorruptStoreFailsClosedAndRegistryContainsNoKey() async throws {
        let file = path()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: file)
        let store = ObservedUsageStore(url: file)
        do { _ = try await store.meters(providerID: config.providerID, productID: config.productID, now: now); XCTFail() } catch {}
        let registry = GenericAPIRegistry(url: path())
        try registry.write([config]); XCTAssertEqual(try registry.read(), [config])
        let fields = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(contentsOf: registry.url)) as? [[String: Any]])?.first)
        XCTAssertEqual(Set(fields.keys), ["id", "name", "baseURL", "model", "apiProtocol"])
    }
    func testGenericProductAndEntitlementComposition() async throws {
        let store = ObservedUsageStore(url: path())
        try await store.append(record(try ResponsesTokenUsage.parse(fixture())))
        let local = try await GenericAPIProduct(configuration: config, store: store).fetchProduct(at: now)
        XCTAssertEqual(local.primary()?.value, 130); XCTAssertEqual(local.primary()?.displayName, "Observed Today")
        let enriched = try await UsageEnrichedProductAdapter(entitlement: EntitlementFixture(descriptor: config.descriptor), store: store).fetchProduct(at: now)
        XCTAssertEqual(enriched.primary()?.kind, .balance); XCTAssertEqual(enriched.meters.count, 4)
        var prefs = PlatformPreferences(); prefs.menuOrder.insert(config.providerID, at: 0)
        prefs.moveProvider(config.providerID, to: "deepseek", including: [config.providerID])
        XCTAssertTrue(prefs.menuOrder.contains(config.providerID)); XCTAssertEqual(prefs.menuOrder, prefs.saverOrder)
    }
    func testDynamicProductRefreshPublishesOnlyAggregatesAndRemovalPersists() async throws {
        let ledger = path(), shared = SnapshotStore(url: path()), display = SnapshotStore(url: path())
        let store = ObservedUsageStore(url: ledger)
        try await store.append(record(try ResponsesTokenUsage.parse(fixture()), at: .now))
        let original = try Data(contentsOf: ledger)
        var preferences = PlatformPreferences()
        let coordinator = ProviderRefreshCoordinator(adapters: [any ProductAdapter](),
            publisher: SnapshotPublisher(shared: shared, display: display), existing: nil, preferences: preferences)
        await coordinator.register(GenericAPIProduct(configuration: config, store: store))
        preferences.enabledProducts.insert(config.productID)
        _ = try await coordinator.configure(preferences)
        await coordinator.refreshAll { _ in }
        let snapshot = try display.read()
        XCTAssertEqual(snapshot.providers.first?.displayName, config.name)
        XCTAssertEqual(snapshot.providers.first?.primaryMeter?.value, 130)
        XCTAssertEqual(try Data(contentsOf: ledger), original, "Automatic refresh only reads the ledger")
        let exported = try String(contentsOf: display.url, encoding: .utf8)
        for forbidden in ["inputTokens", "cachedTokens", "baseURL", config.model, "CONTENT_MUST_NOT_PERSIST"] {
            XCTAssertFalse(exported.contains(forbidden))
        }
        await coordinator.unregister(config.productID)
        preferences.enabledProducts.remove(config.productID)
        _ = try await coordinator.configure(preferences)
        await coordinator.refreshAll { _ in }
        XCTAssertTrue(try shared.read().providers.isEmpty)
        XCTAssertTrue(try display.read().providers.isEmpty)
    }
    func testIntegrationRequestRejectsUnsafeBoundsBeforeSending() async throws {
        let client = ProbeClient(data: try fixture(), status: 200)
        let transport = ResponsesUsageTransport(client: client)
        for (input, maximum) in [("", 16), (String(repeating: "x", count: 65_537), 16), ("fixture", 0), ("fixture", 4097)] {
            do { _ = try await transport.usage(for: config, credential: "test-key", input: input, maxOutputTokens: maximum); XCTFail() }
            catch { XCTAssertEqual(error as? ResponsesUsageError, .configuration) }
        }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
private actor ProbeClient: ProviderHTTPClient {
    let responseData: Data; let status: Int
    var requests: [URLRequest] = []
    init(data: Data, status: Int) { responseData = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (responseData, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private struct TimeoutClient: ProviderHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.timedOut) }
}
private struct EntitlementFixture: ProductAdapter {
    let descriptor: ProductDescriptor
    func fetchProduct(at date: Date) async throws -> ProductQuota {
        ProductQuota(id: descriptor.id, providerID: descriptor.providerID, displayName: descriptor.displayName,
            meters: [.init(id: "balance", displayName: "Balance", kind: .balance, value: 5, currency: "CNY", updatedAt: date, reliability: .officialPublicAPI)], at: date)
    }
}

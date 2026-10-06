import XCTest
@testable import QuotaCore

final class Phase2Tests: XCTestCase {
    private func fixture(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/\(path)").standardizedFileURL)
    }
    func testDeepSeekContractAndPrivacy() throws {
        let date = Date()
        let quota = try DeepSeekBalanceParser.parse(fixture("DeepSeek/balance-cny.json"), at: date)
        XCTAssertEqual(quota.primaryBalance?.total, Decimal(string: "4.90"))
        XCTAssertEqual(quota.primaryBalance?.currency, "CNY")
        XCTAssertEqual(quota.primaryBalance?.formatted(quota.primaryBalance!.total), "¥4.90")
        let mixed = try DeepSeekBalanceParser.parse(fixture("DeepSeek/balance-multiple.json"), at: date)
        XCTAssertEqual(mixed.balances?.count, 2)
        XCTAssertEqual(mixed.primaryBalance?.currency, "CNY")
        XCTAssertEqual(mixed.balanceAvailable, false)
        let usd = try XCTUnwrap(mixed.balances?.first(where: { $0.currency == "USD" }))
        XCTAssertEqual(usd.formatted(usd.total), "$2.25")
        var snapshot = QuotaSnapshot(generatedAt: date, providers: [quota])
        snapshot.heroSelection = .pinned(providerID: "deepseek")
        let encoded = try SnapshotStore.encode(snapshot.displayProjection())
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Authorization"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("api-key"))
        XCTAssertEqual(snapshot.hero?.id, "deepseek")
        for raw in [#"{"is_available":true,"balance_infos":[]}"#,
                    #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"NaN","granted_balance":"0","topped_up_balance":"0"}]}"#,
                    #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1"}]}"#] {
            XCTAssertThrowsError(try DeepSeekBalanceParser.parse(Data(raw.utf8), at: date))
        }
    }
    func testBalanceHeroChangeOnlyForPrimaryTotal() throws {
        let old = try DeepSeekBalanceParser.parse(fixture("DeepSeek/balance-cny.json"), at: .now)
        var next = old
        next.balanceAvailable = false
        next.balances![0].toppedUp = 3
        XCTAssertFalse(ProviderRefreshCoordinator.quotaChanged(old, next))
        next.balances![0].total = 3
        XCTAssertTrue(ProviderRefreshCoordinator.quotaChanged(old, next))
    }
    func testDeepSeekMockTransportAndCoordinatorLastKnown() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: folder.appendingPathComponent("group.json")), display: SnapshotStore(url: folder.appendingPathComponent("display.json")))
        let client = SequenceHTTPClient(data: try fixture("DeepSeek/balance-cny.json"), statuses: [200, 429, 200])
        let adapter = DeepSeekProviderAdapter(credential: { "test-only" }, client: client)
        let coordinator = ProviderRefreshCoordinator(adapters: [adapter], publisher: writer, existing: nil, enabled: ["deepseek"])
        await coordinator.refreshAll(manual: true) { _ in }
        let first = await coordinator.current()
        XCTAssertEqual(first.hero?.primaryBalance?.total, Decimal(string: "4.90"))
        await coordinator.refreshAll(manual: true) { _ in }
        let stale = await coordinator.current()
        XCTAssertEqual(stale.providers[0].health?.state, .stale)
        XCTAssertEqual(stale.hero?.primaryBalance, first.hero?.primaryBalance)
        XCTAssertEqual(stale.hero?.quotaChangedAt, first.hero?.quotaChangedAt)
        await coordinator.refreshAll(manual: true) { _ in }
        let recovered = await coordinator.current()
        XCTAssertEqual(recovered.providers[0].health?.state, .healthy)
        XCTAssertEqual(recovered.hero?.quotaChangedAt, first.hero?.quotaChangedAt)
        XCTAssertEqual(try writer.shared.read().revision, try writer.display.read().revision)
    }
    func testClaudeMockTransport() async throws {
        let data = try fixture("Claude/usage-object.json")
        let good = ClaudeProviderAdapter(credential: { "test-only" }, client: SequenceHTTPClient(data: data, statuses: [200]))
        let result = try await good.fetchQuota(at: .now)
        XCTAssertEqual(result.primaryLimit?.displayName, "Session")
        let auth = ClaudeProviderAdapter(credential: { "test-only" }, client: SequenceHTTPClient(data: data, statuses: [401]))
        do { _ = try await auth.fetchQuota(at: .now); XCTFail("Expected auth failure") }
        catch ProviderFetchError.authenticationRequired { }
        let rate = ClaudeProviderAdapter(credential: { "test-only" }, client: SequenceHTTPClient(data: data, statuses: [429]))
        do { _ = try await rate.fetchQuota(at: .now); XCTFail("Expected rate limit") }
        catch ProviderFetchError.rateLimited { }
    }
    func testDeepSeekErrorStatusesAndMissingCredential() async throws {
        let data = try fixture("DeepSeek/balance-cny.json")
        let missing = DeepSeekProviderAdapter(credential: { nil }, client: SequenceHTTPClient(data: data, statuses: []))
        do { _ = try await missing.fetchQuota(at: .now); XCTFail("Expected missing key") }
        catch ProviderFetchError.authenticationRequired { }
        for status in [401, 403] {
            let adapter = DeepSeekProviderAdapter(credential: { "test-only" }, client: SequenceHTTPClient(data: data, statuses: [status]))
            do { _ = try await adapter.fetchQuota(at: .now); XCTFail("Expected auth failure") }
            catch ProviderFetchError.authenticationRequired { }
        }
        let rate = DeepSeekProviderAdapter(credential: { "test-only" }, client: SequenceHTTPClient(data: data, statuses: [429]))
        do { _ = try await rate.fetchQuota(at: .now); XCTFail("Expected rate limit") }
        catch ProviderFetchError.rateLimited { }
        let malformed = DeepSeekProviderAdapter(credential: { "test-only" }, client: SequenceHTTPClient(data: Data("{}".utf8), statuses: [200]))
        do { _ = try await malformed.fetchQuota(at: .now); XCTFail("Expected parse failure") }
        catch ProviderFetchError.invalidResponse { }
    }
    func testClaudeTransportThroughCoordinatorRecovery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: folder.appendingPathComponent("group.json")), display: SnapshotStore(url: folder.appendingPathComponent("display.json")))
        let client = SequenceHTTPClient(data: try fixture("Claude/usage-object.json"), statuses: [200, 429, 200])
        let adapter = ClaudeProviderAdapter(credential: { "test-only" }, client: client)
        let coordinator = ProviderRefreshCoordinator(adapters: [adapter], publisher: writer, existing: nil, enabled: ["claude-code"])
        await coordinator.refreshAll(manual: true) { _ in }
        let first = await coordinator.current()
        XCTAssertEqual(first.hero?.primaryLimit?.displayName, "Session")
        await coordinator.refreshAll(manual: true) { _ in }
        let stale = await coordinator.current()
        XCTAssertEqual(stale.providers[0].health?.state, .stale)
        XCTAssertEqual(stale.hero?.quotaChangedAt, first.hero?.quotaChangedAt)
        await coordinator.refreshAll(manual: true) { _ in }
        let recovered = await coordinator.current()
        XCTAssertEqual(recovered.providers[0].health?.state, .healthy)
        XCTAssertEqual(recovered.hero?.quotaChangedAt, first.hero?.quotaChangedAt)
        XCTAssertEqual(try writer.shared.read().revision, try writer.display.read().revision)
    }
}

private actor SequenceHTTPClient: ProviderHTTPClient {
    let data: Data
    var statuses: [Int]
    init(data: Data, statuses: [Int]) { self.data = data; self.statuses = statuses }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        let status = statuses.removeFirst()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

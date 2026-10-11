import XCTest
@testable import QuotaCore

final class ClaudeSubscriptionTests: XCTestCase {
    private func parse(_ text: String) throws -> ProviderQuota {
        try ClaudeQuotaParser.parse(Data(text.utf8), at: Date(timeIntervalSince1970: 1_791_590_400))
    }
    func testStructuredWindowsSupplementLegacyAndPreserveScope() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/Claude/usage-wrapped.json")
        let quota = try ClaudeQuotaParser.parse(Data(contentsOf: url), at: .now)
        XCTAssertEqual(quota.limits.map(\.remainingPercentage), [72, 59, 32, 88])
        XCTAssertEqual(quota.limits.map(\.id), ["five_hour", "seven_day", "weekly_scoped.opus", "weekly_scoped.sonnet"])
        XCTAssertEqual(quota.limits.map(\.windowDuration), [18_000, 604_800, 604_800, 604_800])
        XCTAssertEqual(quota.primaryLimit?.id, "five_hour")
        XCTAssertNotEqual(quota.limits[2].resetAt, quota.limits[3].resetAt)
        XCTAssertNil(quota.planName)
        let product = ProductMigration.product(quota)
        XCTAssertEqual(product.meters.map(\.value), [72, 59, 32, 88])
        XCTAssertEqual(product.meters.first?.windowDuration, 18_000)
    }
    func testUnknownOptionalAndNullWindowsDoNotBecomeZero() throws {
        let quota = try parse(#"{"five_hour":null,"seven_day":{"utilization":100,"resets_at":null},"future_field":{}}"#)
        XCTAssertEqual(quota.limits.count, 1)
        XCTAssertEqual(quota.primaryLimit?.remainingPercentage, 0)
        XCTAssertNil(quota.primaryLimit?.resetAt)
        XCTAssertEqual(try parse(#"{"five_hour":{"utilization":0}}"#).primaryLimit?.remainingPercentage, 100)
    }
    func testInvalidKnownWindowsFailRatherThanInventQuota() {
        for text in [
            #"{"limits":[{"kind":"session","percent":true}]}"#,
            #"{"limits":[{"kind":"session","percent":101}]}"#,
            #"{"limits":[{"kind":"session","percent":-1}]}"#,
            #"{"limits":[{"kind":"session","percent":null}]}"#,
            #"{"limits":[{"kind":"session","percent":10,"resets_at":"bad"}]}"#,
            #"{"limits":[{"kind":"weekly_scoped","percent":10}]}"#,
            #"{"limits":[{"kind":"session","percent":10},{"kind":"session","percent":20}]}"#,
            #"{"limits":{},"five_hour":{"utilization":0}}"#,
            #"{"error":"unauthorized","five_hour":{"utilization":0}}"#,
            #"{"limits":[{"kind":"session","is_active":false}]}"#
        ] { XCTAssertThrowsError(try parse(text), text) }
    }
    func testCredentialDecoderRejectsExpiredEmptyAndMalformed() {
        let now = Date(timeIntervalSince1970: 100)
        for value in [#"{"accessToken":" "}"#, #"{"accessToken":"demo","expiresAt":100000}"#,
                      #"{"accessToken":"demo","expiresAt":true}"#] {
            XCTAssertNil(ClaudeCredentialSource.accessToken(in: Data("{\"claudeAiOauth\":\(value)}".utf8), at: now))
        }
        XCTAssertEqual(ClaudeCredentialSource.accessToken(in: Data(#"{"claudeAiOauth":{"accessToken":" demo ","expiresAt":101000}}"#.utf8), at: now), "demo")
    }
    func testFableAndExtraUsageSurviveProductAndDisplayProjection() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/Claude/usage-fable.json")
        var quota = try ClaudeQuotaParser.parse(Data(contentsOf: url), at: .now)
        XCTAssertEqual(quota.limits.last?.displayName, "Fable Weekly")
        XCTAssertEqual(quota.limits.last?.remainingPercentage, 84)
        XCTAssertEqual(quota.bankResetCount, 2)
        XCTAssertEqual(quota.claudeExtraUsage?.used, 2.35)
        XCTAssertEqual(quota.claudeExtraUsage?.limit, 20)
        XCTAssertEqual(quota.claudeExtraUsage?.currency, "USD")
        quota.products = [ProductMigration.product(quota)]
        let projected = QuotaSnapshot(generatedAt: .now, providers: [quota.selecting()]).displayProjection()
        let decoded = try JSONDecoder().decode(QuotaSnapshot.self, from: SnapshotStore.encode(projected))
        XCTAssertEqual(decoded.providers[0].selecting().claudeExtraUsage, quota.claudeExtraUsage)
        XCTAssertEqual(decoded.providers[0].limits.last?.displayName, "Fable Weekly")
        XCTAssertEqual(decoded.providers[0].selecting().bankResetCount, 2)
    }
    func testOptionalExtraUsageNeverInventsIncludedQuota() throws {
        let disabled = try parse(#"{"five_hour":{"utilization":0},"extra_usage":{"is_enabled":false,"used_credits":999}}"#)
        XCTAssertEqual(disabled.claudeExtraUsage, .init(enabled: false))
        let missing = try parse(#"{"seven_day":{"utilization":20},"extra_usage":{"is_enabled":true,"used_credits":null}}"#)
        XCTAssertNil(missing.claudeExtraUsage?.used)
        XCTAssertFalse(missing.limits.contains { $0.id == "five_hour" })
        XCTAssertFalse(missing.limits.contains { $0.displayName == "Fable Weekly" })
        let scaled = try parse(#"{"five_hour":{"utilization":0},"extra_usage":{"is_enabled":true,"decimal_places":3,"used_credits":1250,"currency":"EUR"}}"#)
        XCTAssertEqual(scaled.claudeExtraUsage?.used, 1.25)
        XCTAssertNil(scaled.claudeExtraUsage?.limit)
    }
    func testPlanComesFromCredentialMetadata() {
        XCTAssertEqual(ClaudeCredentialSource.plan(in: Data(#"{"claudeAiOauth":{"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#.utf8)), "Max 20x")
        XCTAssertEqual(ClaudeCredentialSource.plan(in: Data(#"{"claudeAiOauth":{"subscriptionType":"pro"}}"#.utf8)), "Pro")
        XCTAssertNil(ClaudeCredentialSource.plan(in: Data(#"{"claudeAiOauth":{"accessToken":"fixture"}}"#.utf8)))
    }
    func testResetInventoryMissingInvalidAndUnavailableAreUnknown() throws {
        for block in ["null", "{}", #"{"eligible":false,"grants":[]}"#,
                      #"{"grants":[{"resets_left":true}]}"#,
                      #"{"grants":[{"resets_left":1.5}]}"#,
                      #"{"grants":[{"resets_left":-1}]}"#,
                      #"{"grants":[{"resets_left":2,"ends_at":"invalid"}]}"#,
                      #"{"grants":[{"id":"a","resets_left":1},{"id":"a","resets_left":1}]}"#] {
            XCTAssertNil(try parse("{\"five_hour\":{\"utilization\":0},\"cedar_ember\":\(block)}").bankResetCount)
        }
        XCTAssertNil(try parse(#"{"five_hour":{"utilization":0}}"#).bankResetCount)
        XCTAssertEqual(try parse(#"{"five_hour":{"utilization":0},"cedar_ember":{"eligible":true,"grants":[]}}"#).bankResetCount, 0)
    }
    func testResetInventoryCountsOnlyCurrentUnpausedGrants() throws {
        let quota = try parse(#"{"five_hour":{"utilization":0},"cedar_ember":{"grants":[{"resets_left":2,"usable_now":false},{"resets_left":1},{"resets_left":8,"ends_at":"2020-01-01T00:00:00Z"},{"resets_left":8,"starts_at":"2030-01-01T00:00:00Z"},{"resets_left":8,"paused":true}]}}"#)
        XCTAssertEqual(quota.bankResetCount, 3)
    }
    func testOptionalInventoryQueryFallsBackToUsage() async throws {
        for status in [400, 403] {
            let client = ClaudeFallbackHTTP(status: status)
            let quota = try await ClaudeProviderAdapter(credential: { "fixture-token" }, client: client).fetchQuota(at: .now)
            XCTAssertEqual(quota.primaryLimit?.remainingPercentage, 75)
            XCTAssertNil(quota.bankResetCount)
            let queries = await client.queries
            XCTAssertEqual(queries, ["cedar_ember=1", ""])
        }
    }
    func testHTTPContractAndErrors() async throws {
        let quota = try await ClaudeProviderAdapter(credential: { "fixture-token" }, client: ClaudeFixtureHTTP(status: 200)).fetchQuota(at: .now)
        XCTAssertEqual(quota.primaryLimit?.remainingPercentage, 75)
        for (status, state) in [(401, ProviderHealthState.authenticationRequired), (403, .unavailable), (429, .rateLimited), (500, .unavailable), (302, .unavailable)] {
            do {
                _ = try await ClaudeProviderAdapter(credential: { "fixture-token" }, client: ClaudeFixtureHTTP(status: status)).fetchQuota(at: .now)
                XCTFail("Expected HTTP \(status) to fail")
            } catch let error as ProviderFetchError { XCTAssertEqual(error.healthState, state) }
        }
        do {
            _ = try await ClaudeProviderAdapter(credential: { nil }, client: ClaudeFixtureHTTP(status: 200)).fetchQuota(at: .now)
            XCTFail("No credential must not issue a request")
        } catch let error as ProviderFetchError { XCTAssertEqual(error.healthState, .authenticationRequired) }
    }
}
private struct ClaudeFixtureHTTP: ProviderHTTPClient {
    let status: Int
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        XCTAssertEqual(request.url?.host, "api.anthropic.com")
        XCTAssertEqual(request.url?.path, "/api/oauth/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        return (Data(#"{"five_hour":{"utilization":25}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor ClaudeFallbackHTTP: ProviderHTTPClient {
    let status: Int
    var queries: [String] = []
    init(status: Int) { self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        queries.append(request.url?.query ?? "")
        let code = queries.count == 1 ? status : 200
        return (Data(#"{"five_hour":{"utilization":25}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

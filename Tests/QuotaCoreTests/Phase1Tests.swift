import XCTest
@testable import QuotaCore

final class Phase1Tests: XCTestCase {
    private func fixture(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/\(path)").standardizedFileURL)
    }
    func testCodexBundledLauncherDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("ChatGPT.app")
        let launcher = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: launcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        XCTAssertEqual(CodexAppServerTransport.resolveExecutable(applications: [app], home: root), launcher.path)
    }
    func testCodexMappingAndBounds() throws {
        let quota = try CodexQuotaParser.parse(fixture("Codex/rate-limits.json"), at: .now)
        XCTAssertEqual(quota.planName, "Plus")
        XCTAssertEqual(quota.limits.map(\.displayName), ["5-hour", "Weekly"])
        XCTAssertEqual(quota.limits.map(\.remainingPercentage), [74.5, 60])
        XCTAssertEqual(quota.bankResetCount, 2)
        XCTAssertNotNil(quota.limits[0].resetAt)
        let malformed = Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":101}}}}"#.utf8)
        XCTAssertThrowsError(try CodexQuotaParser.parse(malformed, at: .now))
        let missing = Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":"nan"}}}}"#.utf8)
        XCTAssertThrowsError(try CodexQuotaParser.parse(missing, at: .now))
        let proLite = Data(#"{"result":{"rateLimits":{"planType":"prolite","primary":{"usedPercent":71,"windowDurationMins":10080}}}}"#.utf8)
        XCTAssertEqual(try CodexQuotaParser.parse(proLite, at: .now).planName, "Pro 5x")
    }
    func testCodexUsageAggregatesAndSevenDayBound() throws {
        let data = Data(#"{"result":{"summary":{"lifetimeTokens":4134524195,"peakDailyTokens":301547668},"dailyUsageBuckets":[{"startDate":"2026-09-18","tokens":1},{"startDate":"2026-09-19","tokens":2},{"startDate":"2026-09-20","tokens":3},{"startDate":"2026-09-21","tokens":4},{"startDate":"2026-09-22","tokens":5},{"startDate":"2026-09-23","tokens":6},{"startDate":"2026-09-24","tokens":7},{"startDate":"2026-09-25","tokens":74540484}]}}"#.utf8)
        let usage = try CodexUsageParser.parse(data)
        XCTAssertEqual(usage.totalTokens, 4_134_524_195)
        XCTAssertEqual(usage.peakDailyTokens, 301_547_668)
        XCTAssertEqual(usage.lastDailyTokens, 74_540_484)
        XCTAssertEqual(usage.dailyHistory?.count, 7)
        XCTAssertEqual(usage.dailyHistory?.first?.tokens, 2)
        XCTAssertThrowsError(try CodexUsageParser.parse(Data(#"{"result":{}}"#.utf8)))
    }
    func testClaudeTerminologyAndShapes() throws {
        let object = try ClaudeQuotaParser.parse(fixture("Claude/usage-object.json"), at: .now)
        XCTAssertEqual(object.limits.map(\.displayName), ["Session", "Weekly", "Sonnet Weekly"])
        XCTAssertEqual(object.limits.map(\.remainingPercentage), [91, 63.75, 50])
        let rows = try ClaudeQuotaParser.parse(fixture("Claude/usage-rows.json"), at: .now)
        XCTAssertEqual(rows.limits.map(\.displayName), ["Session", "Weekly", "Fable Weekly"])
        XCTAssertEqual(rows.limits.map(\.remainingPercentage), [95, 86, 84])
    }
    func testQuotaChangeIgnoresFreshnessAndHealth() {
        let old = MockProvider.snapshot().providers[0]
        var new = old
        new.lastUpdated = old.lastUpdated.addingTimeInterval(100)
        new.health = ProviderHealth(state: .stale)
        XCTAssertFalse(ProviderRefreshCoordinator.quotaChanged(old, new))
        new.limits[0].remainingPercentage = 60
        XCTAssertTrue(ProviderRefreshCoordinator.quotaChanged(old, new))
        new = old; new.limits[0].resetAt = old.limits[0].resetAt?.addingTimeInterval(120)
        XCTAssertTrue(ProviderRefreshCoordinator.quotaChanged(old, new))
    }
    func testDisplayProjectionAllowsOnlyAggregateUsageAndNoCredential() throws {
        let fixtureBytes = try fixture("Codex/rate-limits.json")
        XCTAssertTrue(String(decoding: fixtureBytes, as: UTF8.self).contains("SECRET_FIXTURE_TOKEN"))
        var snapshot = QuotaSnapshot(generatedAt: .now, providers: [try CodexQuotaParser.parse(fixtureBytes, at: .now)])
        snapshot.providers[0].usage = UsageStatistics(totalTokens: 123, peakDailyTokens: 12,
            lastDailyTokens: 5, dailyHistory: (0..<10).map { UsageDay(date: Date(timeIntervalSince1970: Double($0) * 86400), tokens: Int64($0)) })
        let projected = snapshot.displayProjection()
        let data = try SnapshotStore.encode(projected)
        XCTAssertEqual(projected.providers[0].usage?.totalTokens, 123)
        XCTAssertEqual(projected.providers[0].usage?.peakDailyTokens, 12)
        XCTAssertEqual(projected.providers[0].usage?.dailyHistory?.count, 7)
        XCTAssertEqual(projected.revision, snapshot.revision)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SECRET_FIXTURE_TOKEN"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("totalTokens"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("lastAttempt"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("windowDuration"))
    }
    func testPartialSuccessAndLastKnown() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: folder.appendingPathComponent("group.json")), display: SnapshotStore(url: folder.appendingPathComponent("display.json")))
        let coordinator = ProviderRefreshCoordinator(adapters: [FixtureAdapter(id: "codex", success: true), FixtureAdapter(id: "claude-code", success: false)], publisher: writer, existing: nil, enabled: ["codex", "claude-code"])
        await coordinator.refreshAll(manual: true) { _ in }
        let first = await coordinator.current()
        XCTAssertEqual(first.providers.count, 2)
        XCTAssertEqual(first.providers.first(where: { $0.id == "codex" })?.health?.state, .healthy)
        XCTAssertEqual(first.providers.first(where: { $0.id == "claude-code" })?.health?.state, .authenticationRequired)
        XCTAssertTrue(first.providers.first(where: { $0.id == "claude-code" })?.limits.isEmpty == true)
        XCTAssertEqual(try writer.shared.read().revision, try writer.display.read().revision)
    }
    func testFailureKeepsLastKnownAndRecoveryDoesNotStealHero() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: folder.appendingPathComponent("group.json")), display: SnapshotStore(url: folder.appendingPathComponent("display.json")))
        let adapter = SequencedAdapter(id: "codex", outcomes: [true, false, true])
        let coordinator = ProviderRefreshCoordinator(adapters: [adapter], publisher: writer, existing: nil, enabled: ["codex"])
        await coordinator.refreshAll(manual: true) { _ in }
        let firstSnapshot = await coordinator.current()
        let first = try XCTUnwrap(firstSnapshot.providers.first)
        await coordinator.refreshAll(manual: true) { _ in }
        let failedSnapshot = await coordinator.current()
        let failed = try XCTUnwrap(failedSnapshot.providers.first)
        XCTAssertEqual(failed.limits, first.limits)
        XCTAssertEqual(failed.quotaChangedAt, first.quotaChangedAt)
        XCTAssertEqual(failed.health?.state, .stale)
        XCTAssertEqual(failed.health?.usingLastKnownGood, true)
        await coordinator.refreshAll(manual: true) { _ in }
        let recoveredSnapshot = await coordinator.current()
        let recovered = try XCTUnwrap(recoveredSnapshot.providers.first)
        XCTAssertEqual(recovered.health?.state, .healthy)
        XCTAssertEqual(recovered.quotaChangedAt, first.quotaChangedAt)
        XCTAssertNotEqual(recovered.lastUpdated, first.lastUpdated)
    }
    func testStaleTransitionPreservesQuotaChangeTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: folder.appendingPathComponent("group.json")), display: SnapshotStore(url: folder.appendingPathComponent("display.json")))
        let coordinator = ProviderRefreshCoordinator(adapters: [FixtureAdapter(id: "codex", success: true)], publisher: writer, existing: nil, enabled: ["codex"])
        await coordinator.refreshAll(manual: true) { _ in }
        let initial = await coordinator.current()
        let stale = try await coordinator.markStale(now: Date().addingTimeInterval(901))
        XCTAssertEqual(stale?.providers[0].health?.state, .stale)
        XCTAssertEqual(stale?.providers[0].quotaChangedAt, initial.providers[0].quotaChangedAt)
        XCTAssertEqual(stale?.providers[0].limits, initial.providers[0].limits)
    }
    func testInvalidAdapterValueBecomesErrorWithoutQuota() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: folder.appendingPathComponent("group.json")), display: SnapshotStore(url: folder.appendingPathComponent("display.json")))
        let coordinator = ProviderRefreshCoordinator(adapters: [InvalidAdapter()], publisher: writer, existing: nil, enabled: ["codex"])
        await coordinator.refreshAll(manual: true) { _ in }
        let snapshot = await coordinator.current()
        XCTAssertEqual(snapshot.providers[0].health?.state, .error)
        XCTAssertTrue(snapshot.providers[0].limits.isEmpty)
        XCTAssertEqual(try writer.shared.read().revision, snapshot.revision)
    }
}
private struct FixtureAdapter: ProviderAdapter {
    let id: String
    let success: Bool
    var providerID: String { id }
    func fetchQuota(at date: Date) async throws -> ProviderQuota {
        if !success { throw ProviderFetchError.authenticationRequired }
        return ProviderQuota(id: id, displayName: id, planName: nil, limits: [LimitWindow(id: "main", displayName: "Session", remainingPercentage: 75, isPrimary: true)], lastUpdated: date)
    }
}
private actor SequencedAdapter: ProviderAdapter {
    nonisolated let providerID: String
    private var outcomes: [Bool]
    init(id: String, outcomes: [Bool]) { providerID = id; self.outcomes = outcomes }
    func fetchQuota(at date: Date) async throws -> ProviderQuota {
        if !outcomes.removeFirst() { throw ProviderFetchError.unavailable }
        return ProviderQuota(id: providerID, displayName: "Codex", planName: "Plus", limits: [LimitWindow(id: "main", displayName: "Session", remainingPercentage: 75, isPrimary: true)], lastUpdated: date)
    }
}
private struct InvalidAdapter: ProviderAdapter {
    let providerID = "codex"
    func fetchQuota(at date: Date) async throws -> ProviderQuota {
        ProviderQuota(id: providerID, displayName: "Codex", planName: nil,
            limits: [LimitWindow(id: "main", displayName: "Weekly", remainingPercentage: 101)], lastUpdated: date)
    }
}

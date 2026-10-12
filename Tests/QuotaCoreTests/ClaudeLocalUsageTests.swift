import XCTest
@testable import QuotaCore

final class ClaudeLocalUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-12T10:00:00Z")!
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private func line(id: String = "msg", session: String = "session", output: Int = 7, timestamp: String = "2026-10-11T18:00:00Z", extra: [String: Any] = [:]) throws -> Data {
        var root: [String: Any] = ["type": "assistant", "sessionId": session, "requestId": "request", "timestamp": timestamp,
           "message": ["id": id, "model": "claude-test", "usage": ["input_tokens": 10, "output_tokens": output, "cache_creation_input_tokens": 20, "cache_read_input_tokens": 30]]]
        root.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: root) + Data([10])
    }
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func write(_ data: Data, _ path: String, home: URL) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func testCacheInclusiveTotalsFinalChunkAndLocalDays() throws {
        let data = try line(output: 3) + line(output: 7) + line(id: "yesterday", output: 9, timestamp: "2026-10-11T12:00:00Z")
        let rows = try ClaudeLocalUsage.parse(data, path: "/project/s.jsonl", desktop: false)
        let usage = try ClaudeLocalUsage.aggregate(rows: rows, scope: .claudeCLI, at: now, calendar: calendar)
        XCTAssertEqual(usage.totalTokens, 136) // final cumulative chunk 67 + separate request 69
        XCTAssertEqual(usage.peakDailyTokens, 69)
        XCTAssertEqual(usage.lastDailyTokens, 69)
        XCTAssertEqual(usage.dailyHistory?.count, 7)
        XCTAssertEqual(usage.dailyHistory?.last?.date, ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z"))
        XCTAssertEqual(usage.dailyHistory?.dropLast().map(\.tokens), [0,0,0,0,0,0])
    }
    func testParentCopyWinsAndDesktopAttributionSurvivesDedup() throws {
        let parent = try ClaudeLocalUsage.parse(line(output: 7), path: "/a/p.jsonl", desktop: false)
        let subagent = try ClaudeLocalUsage.parse(line(output: 20, extra: ["isSidechain": true]), path: "/b/subagents/a.jsonl", desktop: true)
        let desktop = try ClaudeLocalUsage.aggregate(rows: parent + subagent, scope: .claudeDesktop, at: now, calendar: calendar)
        XCTAssertEqual(desktop.totalTokens, 67)
        XCTAssertNil(try ClaudeLocalUsage.aggregate(rows: parent + subagent, scope: .claudeCLI, at: now, calendar: calendar).totalTokens)
    }
    func testIncompleteProxyChunkDoesNotReplaceComplete() throws {
        let incomplete: [String: Any] = ["id": "msg", "stop_reason": NSNull(), "usage": ["input_tokens": 999, "output_tokens": 0]]
        let rows = try ClaudeLocalUsage.parse(line() + line(extra: ["message": incomplete]), path: "/a/s.jsonl", desktop: false)
        XCTAssertEqual(try ClaudeLocalUsage.aggregate(rows: rows, scope: .claudeCLI, at: now, calendar: calendar).totalTokens, 67)
    }
    func testInvalidNumbersAndPartialAppend() throws {
        for value: Any in [true, -1, 1.5] {
            XCTAssertThrowsError(try ClaudeLocalUsage.parse(line(extra: ["message": ["usage": ["input_tokens": value]]]), path: "/x", desktop: false))
        }
        XCTAssertEqual(try ClaudeLocalUsage.parse(line() + Data("{\"type\":".utf8), path: "/x", desktop: false).count, 1)
        XCTAssertThrowsError(try ClaudeLocalUsage.parse(Data("broken\n".utf8), path: "/x", desktop: false))
    }
    func testDesktopLinksAndEmbeddedLogsExcludeCLIAndRefreshCache() async throws {
        let root = try home(), scanner = ClaudeLocalUsage()
        try write(line(id: "shared", session: "linked"), ".claude/projects/p/linked.jsonl", home: root)
        try write(line(id: "cli", session: "cli"), ".claude/projects/p/cli.jsonl", home: root)
        try write(Data(#"{"cliSessionId":"linked"}"#.utf8), "Library/Application Support/Claude/claude-code-sessions/a/session.json", home: root)
        try write(line(id: "embedded", session: "embedded"), "Library/Application Support/Claude/local-agent-mode-sessions/a/local_agent/.claude/projects/p/e.jsonl", home: root)
        let desktop = await scanner.statistics(scope: .claudeDesktop, at: now, home: root, calendar: calendar)
        let cli = await scanner.statistics(scope: .claudeCLI, at: now, home: root, calendar: calendar)
        XCTAssertEqual(desktop.totalTokens, 134); XCTAssertEqual(cli.totalTokens, 67)
        try write(line(id: "cli", session: "cli", output: 17), ".claude/projects/p/cli.jsonl", home: root)
        let changed = await scanner.statistics(scope: .claudeCLI, at: now, home: root, calendar: calendar, force: true)
        XCTAssertEqual(changed.totalTokens, 77)
        // Copying the same request into another project cannot double the total.
        try write(line(id: "cli", session: "cli", output: 17), ".claude/projects/q/copy.jsonl", home: root)
        let duplicate = await scanner.statistics(scope: .claudeCLI, at: now, home: root, calendar: calendar, force: true)
        XCTAssertEqual(duplicate.totalTokens, 77)
    }
    func testMissingAndMalformedAreNotZero() async throws {
        let root = try home(), scanner = ClaudeLocalUsage()
        let missing = await scanner.statistics(scope: .claudeDesktop, at: now, home: root, calendar: calendar)
        XCTAssertEqual(missing.localStatus, .noRecords); XCTAssertNil(missing.totalTokens); XCTAssertNil(missing.dailyHistory)
        try write(Data("not-json\n".utf8), ".claude/projects/p/bad.jsonl", home: root)
        let broken = await scanner.statistics(scope: .claudeCLI, at: now, home: root, calendar: calendar, force: true)
        XCTAssertEqual(broken.localStatus, .incomplete); XCTAssertNil(broken.totalTokens)
    }
    func testSymlinksAreNotTraversed() async throws {
        let root = try home(), outside = try home()
        try write(line(), "p/s.jsonl", home: outside)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".claude/projects"), withDestinationURL: outside)
        let usage = await ClaudeLocalUsage().statistics(scope: .claudeCLI, at: now, home: root, calendar: calendar)
        XCTAssertEqual(usage.localStatus, .noRecords)
    }
    func testOnlyTodayHasZeroCompletedDaysAndFutureRowsIgnored() throws {
        let rows = try ClaudeLocalUsage.parse(line() + line(id: "future", timestamp: "2027-01-01T00:00:00Z"), path: "/p/s.jsonl", desktop: true)
        let stats = try ClaudeLocalUsage.aggregate(rows: rows, scope: .claudeDesktop, at: now, calendar: calendar)
        XCTAssertEqual(stats.totalTokens, 67)
        XCTAssertEqual(stats.dailyHistory?.map(\.tokens), [0,0,0,0,0,0,0])
        XCTAssertEqual(stats.lastDailyTokens, 0)
    }
    func testScopeSurvivesCodable() throws {
        let old = Data(#"{"totalTokens":12}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(UsageStatistics.self, from: old).localScope)
        let value = UsageStatistics(totalTokens: 42, localScope: .claudeDesktop, localStatus: .available)
        XCTAssertEqual(try JSONDecoder().decode(UsageStatistics.self, from: JSONEncoder().encode(value)), value)
        var provider = ProviderQuota(id: "claude-code", displayName: "Claude", planName: "Pro", limits: [], lastUpdated: now)
        provider.usage = value
        let display = QuotaSnapshot(generatedAt: now, providers: [provider]).displayProjection()
        XCTAssertEqual(display.providers.first?.usage?.localScope, .claudeDesktop)
        XCTAssertEqual(display.providers.first?.usage?.totalTokens, 42)
        XCTAssertEqual(display.providers.first?.usage?.localStatus, .available)
    }
}

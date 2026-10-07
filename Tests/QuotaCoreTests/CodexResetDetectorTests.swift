import XCTest
@testable import QuotaCore

final class CodexResetDetectorTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    func snapshot(_ elapsed: Double, reset: Double, id: String = "codex.account.a", weekly: Bool = false, health: ProviderHealthState = .healthy) -> QuotaSnapshot {
        let now = start.addingTimeInterval(elapsed)
        var provider = ProviderQuota(id: id, displayName: "Codex", planName: nil,
            limits: [LimitWindow(id: "codex.primary", displayName: "Quota", remainingPercentage: 50,
                resetAt: start.addingTimeInterval(reset), windowDuration: weekly ? 604800 : 18000)], lastUpdated: now)
        provider.health = ProviderHealth(state: health, usingLastKnownGood: health != .healthy)
        return QuotaSnapshot(generatedAt: now, providers: [provider])
    }
    func consume(_ d: inout CodexResetDetector, _ s: QuotaSnapshot) -> [CodexResetDetector.Event] {
        d.consume(s, now: s.generatedAt)
    }
    func testFirstSampleCountdownAndDuplicateDoNotNotify() {
        var d = CodexResetDetector()
        XCTAssertTrue(consume(&d, snapshot(0, reset: 60)).isEmpty)
        XCTAssertTrue(consume(&d, snapshot(61, reset: 60)).isEmpty)
        // A delayed server rollover still uses the last valid baseline.
        XCTAssertEqual(consume(&d, snapshot(62, reset: 18060)).count, 1)
    }
    func testFiveHourAndWeeklyRolloverAreIndependentAndPersisted() throws {
        for weekly in [false, true] {
            var d = CodexResetDetector()
            XCTAssertTrue(consume(&d, snapshot(0, reset: 60, weekly: weekly)).isEmpty)
            d = try JSONDecoder().decode(CodexResetDetector.self, from: JSONEncoder().encode(d))
            let next = snapshot(61, reset: weekly ? 604860 : 18060, weekly: weekly)
            let events = consume(&d, next)
            XCTAssertEqual(events.count, 1); XCTAssertEqual(events.first?.weekly, weekly)
            XCTAssertTrue(consume(&d, next).isEmpty)
            XCTAssertTrue(consume(&d, snapshot(62, reset: weekly ? 604860 : 18060, weekly: weekly)).isEmpty)
        }
    }
    func testUnhealthyAndOutOfOrderSamplesCannotCreateResets() {
        var d = CodexResetDetector()
        _ = consume(&d, snapshot(0, reset: 60))
        XCTAssertTrue(consume(&d, snapshot(61, reset: 18060, health: .stale)).isEmpty)
        XCTAssertTrue(consume(&d, snapshot(-1, reset: 18060)).isEmpty)
        XCTAssertEqual(consume(&d, snapshot(62, reset: 18060)).count, 1)
    }
    func testAccountRemovalAndNewAccountDoNotNotify() {
        var d = CodexResetDetector()
        _ = consume(&d, snapshot(0, reset: 60))
        XCTAssertTrue(consume(&d, snapshot(61, reset: 18060, id: "codex.account.b")).isEmpty)
        XCTAssertTrue(consume(&d, snapshot(62, reset: 18060)).isEmpty)
    }
    func testTimeCorrectionOtherProviderAndOldCacheAreIgnored() {
        var d = CodexResetDetector()
        _ = consume(&d, snapshot(0, reset: 60))
        XCTAssertTrue(consume(&d, snapshot(10, reset: 18060)).isEmpty)
        XCTAssertTrue(consume(&d, snapshot(61, reset: 18061, id: "claude")).isEmpty)
        var cold = CodexResetDetector()
        XCTAssertTrue(cold.consume(snapshot(0, reset: 60), now: start.addingTimeInterval(600)).isEmpty)
        XCTAssertTrue(consume(&cold, snapshot(601, reset: 18060)).isEmpty)
    }
}

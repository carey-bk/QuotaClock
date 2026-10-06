import XCTest
@testable import QuotaCore

final class DeepSeekLocalUsageTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!; return c }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")! }
    private func data(model: String = "deepseek-v4-flash", input: Any = 100, day: String = "2026-09-27") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "days": [day: ["deepseek-official": [model: ["inputTokens": input, "outputTokens": 20, "cacheReadTokens": 200, "cacheWriteTokens": 30, "reasoningTokens": 15, "cost": 0.0012]], "other-provider": ["model": ["inputTokens": 999999]]]]])
    }
    func testTokensExcludeReasoningDoubleCountAndOtherProviders() throws {
        let meters = try DeepSeekLocalUsage.meters(data: data(), at: now, calendar: calendar)
        XCTAssertEqual(meters.count, 2)
        XCTAssertEqual(meters[0].value, 350)
        XCTAssertEqual(NSDecimalNumber(decimal: meters[1].value).doubleValue, 0.0012, accuracy: 1e-12)
        XCTAssertEqual(meters[1].currency, "CNY")
        XCTAssertFalse(meters[0].primaryEligible)
        XCTAssertEqual(meters[0].resetAt, ISO8601DateFormatter().date(from: "2026-09-27T16:00:00Z"))
    }
    func testMissingTodayIsUnknownNotZeroAndResetsAtLocalMidnight() throws {
        XCTAssertTrue(try DeepSeekLocalUsage.meters(data: data(day: "2026-09-26"), at: now, calendar: calendar).isEmpty)
        let midnight = ISO8601DateFormatter().date(from: "2026-09-27T16:00:00Z")!
        XCTAssertTrue(try DeepSeekLocalUsage.meters(data: data(), at: midnight, calendar: calendar).isEmpty)
    }
    func testUnverifiedModelPriceIsNotPresentedAsCost() throws {
        for model in ["deepseek-v4-pro", "unknown-model"] {
            let meters = try DeepSeekLocalUsage.meters(data: data(model: model), at: now, calendar: calendar)
            XCTAssertEqual(meters.map(\.id), ["local.today.tokens"])
            XCTAssertEqual(meters[0].value, 350)
        }
    }
    func testMalformedTokensDoNotBecomeUsage() throws {
        for input: Any in [-1, true, 1.5, "100", 1e25] {
            XCTAssertThrowsError(try DeepSeekLocalUsage.meters(data: data(input: input), at: now, calendar: calendar))
        }
    }
}

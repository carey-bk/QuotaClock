import XCTest
@testable import QuotaCore

final class QuotaFreshnessTests: XCTestCase {
    func testPublicationAndAttemptCannotMakeOldQuotaFresh() {
        let now = Date()
        var p = ProviderQuota(id: "codex", displayName: "Codex", planName: nil, limits: [], lastUpdated: now)
        let old = now.addingTimeInterval(-86400)
        p.health = ProviderHealth(state: .stale, lastAttempt: now, lastSuccess: old, usingLastKnownGood: true)
        XCTAssertEqual(p.successfulQuotaUpdate, old)
        XCTAssertTrue(p.isQuotaStale(at: now))
        p.health = ProviderHealth(state: .healthy, lastSuccess: old)
        XCTAssertTrue(p.isQuotaStale(at: now))
        p.health = ProviderHealth(state: .healthy, lastSuccess: now)
        XCTAssertFalse(p.isQuotaStale(at: now))
        p.health = ProviderHealth(state: .unavailable, lastAttempt: now)
        XCTAssertNil(p.successfulQuotaUpdate)
        XCTAssertTrue(p.isQuotaStale(at: now))
    }
}

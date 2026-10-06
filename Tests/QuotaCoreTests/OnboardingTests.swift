import XCTest
@testable import QuotaCore

final class OnboardingTests: XCTestCase {
    func testAppearanceIsSecondWithoutChangingPersistedLegacySteps() throws {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .appearance, .connection, .display, .ready])
        XCTAssertEqual(OnboardingStep.welcome.offset(by: 1), .appearance)
        XCTAssertEqual(OnboardingStep.appearance.offset(by: 1), .connection)
        XCTAssertEqual(OnboardingStep.connection.offset(by: -1), .appearance)
        XCTAssertNil(OnboardingStep.ready.offset(by: 1))
        for (raw, expected) in [(0, OnboardingStep.welcome), (1, .connection), (2, .display), (3, .ready)] {
            let data = Data("{\"step\":\(raw),\"disposition\":\"deferred\"}".utf8)
            let progress = try JSONDecoder().decode(OnboardingProgress.self, from: data)
            XCTAssertEqual(progress.step, expected)
            XCTAssertEqual(progress.disposition, .deferred)
        }
    }
    func testResumeDeferAndRevisitPreserveFirstCompletion() throws {
        let suite = "quotaclock.onboarding.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var progress = OnboardingProgress.load(defaults: defaults)
        XCTAssertTrue(progress.shouldPresentAutomatically)
        progress.move(to: .connection)
        try progress.save(defaults: defaults)
        XCTAssertEqual(OnboardingProgress.load(defaults: defaults).step, .connection)
        progress.deferSetup(); try progress.save(defaults: defaults)
        XCTAssertFalse(OnboardingProgress.load(defaults: defaults).shouldPresentAutomatically)
        XCTAssertNil(progress.completedAt)
        let first = Date(timeIntervalSince1970: 100)
        progress.finish(at: first)
        progress.move(to: .welcome); progress.deferSetup()
        progress.finish(at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(progress.disposition, .completed)
        XCTAssertEqual(progress.completedAt, first)
    }
    func testFreshInstallDoesNotStartOrLinkProviders() {
        let suite = "quotaclock.first-run.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = PlatformPreferences.load(defaults: defaults)
        XCTAssertTrue(fresh.enabledProducts.isEmpty)
        XCTAssertTrue(fresh.codexMultiAccount)
        defaults.set(true, forKey: "provider.codex.enabled")
        XCTAssertTrue(PlatformPreferences.load(defaults: defaults).enabledProducts.contains("codex.subscription"))
    }
    func testUnavailableOrStaleMetricsNeverCountAsReady() {
        var provider = ProviderQuota(id: "codex", displayName: "Codex", planName: nil,
            limits: [.init(id: "session", displayName: "Session", remainingPercentage: 42)], lastUpdated: Date())
        XCTAssertFalse(OnboardingReadiness.usable(provider))
        for state in [ProviderHealthState.error, .stale, .authenticationRequired, .rateLimited, .unavailable] {
            provider.health = .init(state: state)
            XCTAssertFalse(OnboardingReadiness.usable(provider))
        }
        provider.health = .init(state: .healthy)
        XCTAssertTrue(OnboardingReadiness.usable(provider))
        provider.limits = []
        XCTAssertFalse(OnboardingReadiness.usable(provider))
    }
}

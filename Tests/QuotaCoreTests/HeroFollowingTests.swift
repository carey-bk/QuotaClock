import XCTest
@testable import QuotaCore

final class HeroFollowingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func account(_ name: String, current: Bool, changed: TimeInterval) -> ProviderQuota {
        var value = ProviderQuota(id: "codex", displayName: "Codex", planName: "Plus", limits: [
            LimitWindow(id: "5h", displayName: "5-hour", remainingPercentage: 60, resetAt: nil, isPrimary: true),
            LimitWindow(id: "week", displayName: "Weekly", remainingPercentage: 20, resetAt: nil)
        ], lastUpdated: date, quotaChangedAt: date.addingTimeInterval(changed))
        let identity = AccountPresentation(id: UUID(), signature: name, isCurrent: current)
        var product = ProductMigration.product(value); product.account = identity
        product.id = "codex.subscription.account." + identity.id.uuidString.lowercased()
        value.id = product.sourceID; value.products = [product]; value.account = identity
        value.displayPreference = .init()
        return value
    }
    private func snapshot() -> QuotaSnapshot {
        var value = QuotaSnapshot(generatedAt: date, providers: [account("Work", current: true, changed: 1), account("Backup", current: false, changed: 2)])
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = true
        value.platformPreferences = prefs
        return value
    }
    private func switchAccount(_ value: inout QuotaSnapshot) {
        for index in value.providers.indices {
            value.providers[index].account?.isCurrent = index == 1
            let presentation = value.providers[index].account
            value.providers[index].products?[0].account = presentation
        }
    }
    private func other() -> ProviderQuota {
        ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: nil, limits: [
            LimitWindow(id: "session", displayName: "Session", remainingPercentage: 80, resetAt: nil, isPrimary: true)
        ], lastUpdated: date, quotaChangedAt: date.addingTimeInterval(5))
    }
    func testLegacyAccountPinAndCodexPinFollowCurrentAcrossSurfacesAndRoundTrip() throws {
        var value = snapshot(); value.heroSelection = .pinned(providerID: value.providers[0].id)
        XCTAssertEqual(value.hero?.account?.signature, "Work")
        switchAccount(&value)
        for surface in DisplaySurface.allCases { XCTAssertEqual(value.forSurface(surface).hero?.account?.signature, "Backup") }
        let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: SnapshotStore.encode(value.displayProjection()))
        XCTAssertEqual(restored.hero?.account?.signature, "Backup")
        value.heroSelection = .pinned(providerID: "codex")
        XCTAssertEqual(value.hero?.account?.signature, "Backup")
        XCTAssertFalse(value.pinnedHeroUnavailable)
    }
    func testAutomaticCodexHeroUsesCurrentInsteadOfRecentlyChangedInactiveAccount() {
        var value = snapshot()
        XCTAssertEqual(value.hero?.account?.signature, "Work")
        switchAccount(&value)
        XCTAssertEqual(value.hero?.account?.signature, "Backup")
        value.providers.append(other())
        XCTAssertEqual(value.hero?.id, "claude-code")
    }
    func testNonCodexPinnedHeroDoesNotChangeOnCodexSwitch() {
        var value = snapshot(); value.providers.append(other()); value.heroSelection = .pinned(providerID: "claude-code")
        switchAccount(&value)
        XCTAssertEqual(value.hero?.id, "claude-code")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.id, "claude-code")
    }
    func testMissingOrDisabledCurrentAccountNeverShowsPreviousAccountAsHero() {
        var value = snapshot(); value.heroSelection = .pinned(providerID: value.providers[1].id)
        value.providers.removeFirst()
        XCTAssertTrue(value.pinnedHeroUnavailable)
        XCTAssertNil(value.hero?.account)
        XCTAssertNil(value.hero?.primaryMeter)
        XCTAssertEqual(value.hero?.health?.reason, "Current Codex account unavailable")
    }
    func testHiddenCurrentAccountDoesNotPromoteInactiveAccount() {
        var value = snapshot(); value.heroSelection = .pinned(providerID: "codex")
        value.providers[0].displayPreference?.screenSaverVisible = false
        XCTAssertNil(value.forSurface(.screenSaver).hero?.account)
        XCTAssertEqual(value.forSurface(.menuBar).hero?.account?.signature, "Work")
    }
    func testHeroWidgetIgnoresStaleMetricAndLegacyProviderWhileExplicitWidgetStaysFixed() {
        var value = snapshot(); value.heroSelection = .pinned(providerID: "codex")
        let fixed = value.providers[0]
        let metric = [fixed.id, fixed.activeProducts[0].id, "week"]
        switchAccount(&value)
        let hero = WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: metric, legacyProviderID: "claude-code")
        XCTAssertEqual(hero?.account?.signature, "Backup")
        XCTAssertEqual(hero?.primaryMeter?.id, value.hero?.primaryMeter?.id)
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: fixed.id, metric: metric)?.account?.signature, "Work")
    }
    func testHeroWidgetDoesNotChooseAnotherProviderWhenCanonicalHeroIsHidden() {
        var value = snapshot(); value.providers.append(other()); value.heroSelection = .pinned(providerID: "codex")
        value.providers[0].displayPreference?.availableInWidgets = false
        let widget = WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)
        XCTAssertEqual(widget?.health?.reason, "Hero unavailable in Widgets")
        XCTAssertNil(widget?.primaryMeter)
        XCTAssertNotEqual(widget?.id, "claude-code")
    }
    func testFixedAndLegacyWidgetSelectionsKeepUnavailableAndMetricSemantics() {
        let value = snapshot(), fixed = value.providers[1]
        let meter = fixed.activeProducts[0].meters.last!
        let metric = [fixed.id, fixed.activeProducts[0].id, meter.id]
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: nil, metric: metric)?.primaryMeter?.id, meter.id)
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: fixed.id, metric: nil)?.id, fixed.id)
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: "removed", metric: nil)?.health?.reason, "Selected account unavailable")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: nil, metric: [])?.health?.reason, "Selected product or metric unavailable")
    }
    func testSingleAccountAndEmptySnapshotsRemainCompatible() {
        var value = QuotaSnapshot(generatedAt: date, providers: [])
        XCTAssertNil(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil))
        value.providers = [ProviderQuota(id: "codex", displayName: "Codex", planName: nil, limits: [], lastUpdated: date)]
        value.heroSelection = .pinned(providerID: "codex")
        XCTAssertEqual(value.hero?.id, "codex")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: nil, metric: nil, legacyProviderID: "codex")?.id, "codex")
    }
}

import XCTest
@testable import QuotaCore

final class SurfaceConfigurationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func snapshot() -> QuotaSnapshot {
        let providers = ["deepseek", "kimi", "claude-code", "glm"].map { id in
            ProviderQuota(id: id, displayName: ProviderCatalog.name(id), planName: nil,
                          limits: [LimitWindow(id: "quota", displayName: "Quota", remainingPercentage: 42, isPrimary: true)], lastUpdated: date)
        }
        var value = QuotaSnapshot(generatedAt: date, providers: providers)
        var preferences = PlatformPreferences()
        preferences.connectionOrder = providers.map(\.id)
        preferences.surfaces = SurfaceConfiguration(menu: ["kimi", "deepseek"], hero: "glm", secondary: ["claude-code", "deepseek"])
        value.platformPreferences = preferences
        return value
    }
    func testSurfacesRemainIndependentAndLegacyTogglesDoNotHideConnections() {
        var value = snapshot()
        for i in value.providers.indices {
            var old = ProviderDisplayPreference(); old.menuBarVisible = false; old.screenSaverVisible = false
            old.availableInWidgets = false; old.heroEligible = false; value.providers[i].displayPreference = old
        }
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ["kimi", "deepseek"])
        XCTAssertEqual(value.forSurface(.screenSaver).providers.map(\.id), ["glm", "claude-code", "deepseek"])
        XCTAssertEqual(value.forSurface(.widget).providers.count, 4)
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.id, "glm")
        XCTAssertEqual(MenuBarIndicator(snapshot: value).providerID, "kimi")
        value.platformPreferences?.surfaces?.setMenu("claude-code", at: 0)
        XCTAssertEqual(value.hero?.id, "glm")
        XCTAssertEqual(value.saverSecondaryProviders(portrait: false).map(\.id), ["claude-code", "deepseek"])
        value.platformPreferences?.surfaces?.hero = "deepseek"
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ["claude-code", "deepseek"])
        XCTAssertEqual(value.forSurface(.widget).providers.count, 4)
    }
    func testThreeSlotsDeduplicateAndRoundTripWithoutCollapsingEmptySlots() throws {
        var selections = SurfaceConfiguration(menu: ["a", "a", "b", "c"], hero: "", secondary: ["", "b", "c"])
        XCTAssertEqual(selections.menu, ["a", "", "b"])
        XCTAssertEqual(selections.secondary, ["", "b"])
        XCTAssertFalse(selections.hero.isEmpty)
        selections.setMenu("b", at: 0)
        XCTAssertEqual(selections.menu, ["b", "", ""])
        selections.setSecondary("b", at: 0)
        XCTAssertEqual(selections.secondary, ["b", ""])
        XCTAssertEqual(try JSONDecoder().decode(SurfaceConfiguration.self, from: JSONEncoder().encode(selections)), selections)
    }
    func testReorderingConnectionsPersistsWithoutChangingSurfaceSelections() throws {
        var preferences = try XCTUnwrap(snapshot().platformPreferences)
        let original = preferences
        preferences.reorderConnections(["kimi", "removed", "kimi", "deepseek"], available: ["deepseek", "kimi", "claude-code", "glm"])
        XCTAssertEqual(preferences.connectionOrder, ["kimi", "deepseek", "claude-code", "glm"])
        XCTAssertEqual(preferences.surfaces, original.surfaces)
        XCTAssertEqual(preferences.menuOrder, original.menuOrder)
        XCTAssertEqual(preferences.saverOrder, original.saverOrder)
        let suite = "quotaclock-order-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try preferences.save(defaults: defaults)
        XCTAssertEqual(PlatformPreferences.load(defaults: defaults), preferences)
    }
    func testMigrationPreservesLegacyOrderVisibilityAndHero() {
        var value = snapshot(); value.platformPreferences?.surfaces = nil
        value.platformPreferences?.menuOrder = ["kimi", "deepseek", "glm", "claude-code"]
        value.platformPreferences?.saverOrder = ["claude-code", "deepseek", "kimi", "glm"]
        value.heroSelection = .pinned(providerID: "deepseek")
        var hidden = ProviderDisplayPreference(); hidden.menuBarVisible = false
        value.providers[1].displayPreference = hidden
        let next = SurfaceConfiguration.migrating(value)
        XCTAssertEqual(next.menu, ["deepseek", "glm", "claude-code"])
        XCTAssertEqual(next.hero, "deepseek")
        XCTAssertEqual(next.secondary, ["claude-code", "kimi"])
    }
    func testMissingHeroNeverSubstitutesAnotherProviderAndEmptyMenuStaysEmpty() {
        var value = snapshot(); value.platformPreferences?.surfaces = SurfaceConfiguration(hero: "removed")
        XCTAssertEqual(value.hero?.id, "removed")
        XCTAssertEqual(value.hero?.health?.state, .unavailable)
        XCTAssertNil(value.hero?.primaryMeter)
        XCTAssertTrue(value.forSurface(.menuBar).providers.isEmpty)
        XCTAssertEqual(MenuBarIndicator(snapshot: value).text, "—")
        XCTAssertEqual(value.forSurface(.screenSaver).providers.count, 1)
    }
    func testPortraitUsesSlotOneOnlyEvenWhenItIsEmptyOrDuplicatesHero() {
        var value = snapshot()
        XCTAssertEqual(value.saverSecondaryProviders(portrait: true).map(\.id), ["claude-code"])
        value.platformPreferences?.surfaces?.secondary = ["", "deepseek"]
        XCTAssertTrue(value.saverSecondaryProviders(portrait: true).isEmpty)
        XCTAssertEqual(value.saverSecondaryProviders(portrait: false).map(\.id), ["deepseek"])
        value.platformPreferences?.surfaces?.secondary = ["glm", "deepseek"]
        XCTAssertTrue(value.saverSecondaryProviders(portrait: true).isEmpty)
    }
    func testCodexHeroFollowsLoginWhileMenuAndSecondaryStayFixed() {
        var value = snapshot()
        let accounts = [AccountPresentation(id: UUID(), signature: "Work", isCurrent: true), AccountPresentation(id: UUID(), signature: "Home")]
        for account in accounts {
            var provider = ProviderQuota(id: DisplaySourceID.make(provider: "codex", account: account.id), displayName: "Codex", planName: nil, limits: [], lastUpdated: date)
            var product = ProductQuota(id: "codex.subscription.account." + account.id.uuidString.lowercased(), providerID: "codex", displayName: "Codex", meters: [], at: date)
            product.account = account; provider.products = [product]; provider.account = account; value.providers.append(provider)
        }
        let ids = Array(value.providers.suffix(2).map(\.id))
        value.platformPreferences?.surfaces = SurfaceConfiguration(menu: ids, hero: "codex", secondary: ["deepseek"])
        XCTAssertEqual(value.hero?.id, ids[0])
        value.providers[4].account?.isCurrent = false; value.providers[5].account?.isCurrent = true
        XCTAssertEqual(value.hero?.id, ids[1])
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ids)
        XCTAssertEqual(value.saverSecondaryProviders(portrait: false).map(\.id), ["deepseek"])
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.id, ids[1])
    }
    func testNicknameSurvivesDisplayProjectionAndWidgetChoice() throws {
        var value = snapshot(); var pref = ProviderDisplayPreference(); pref.nickname = "Work"
        value.providers[0].displayPreference = pref
        let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: SnapshotStore.encode(value.displayProjection()))
        XCTAssertEqual(restored.providers[0].sourceTitle, "DeepSeek Work")
        XCTAssertEqual(WidgetAccountSelection.accounts(in: restored, providerID: "deepseek").first?.nickname, "Work")
    }
    func testClockFormatAndAMPMChoicePersist() throws {
        var prefs = AmbientPreferences(); prefs.timeFormat = .twelveHour; prefs.showAMPM = false
        let next = try JSONDecoder().decode(AmbientPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertFalse(next.showAMPM)
        let plain = AmbientTimeText.time(date, format: .twelveHour, showAMPM: false, locale: Locale(identifier: "zh_CN"))
        let marked = AmbientTimeText.time(date, format: .twelveHour, showAMPM: true, locale: Locale(identifier: "zh_CN"))
        XCTAssertFalse(plain.contains("AM") || plain.contains("PM"))
        XCTAssertTrue(marked.contains("AM") || marked.contains("PM"))
        XCTAssertEqual(AmbientTimeText.time(date, format: .twentyFourHour, showAMPM: true), AmbientTimeText.time(date, format: .twentyFourHour, showAMPM: false))
        XCTAssertTrue(try JSONDecoder().decode(AmbientPreferences.self, from: Data("{}".utf8)).showAMPM)
    }
}

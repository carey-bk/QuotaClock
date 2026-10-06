import XCTest
@testable import QuotaCore

final class WidgetAccountSelectionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func source(_ id: String, signature: String? = nil, current: Bool = false) -> ProviderQuota {
        var value = ProviderQuota(id: id, displayName: ProviderCatalog.name(id), planName: nil, limits: [
            LimitWindow(id: "short", displayName: "Short", remainingPercentage: 60, resetAt: nil, isPrimary: true),
            LimitWindow(id: "long", displayName: "Long", remainingPercentage: 30, resetAt: nil)
        ], lastUpdated: date)
        var product = ProductMigration.product(value)
        if let signature {
            let account = AccountPresentation(id: UUID(), signature: signature, isCurrent: current)
            product.account = account; product.id = "codex.subscription.account." + account.id.uuidString.lowercased()
            value.account = account; value.id = product.sourceID
        }
        value.products = [product]; value.displayPreference = .init()
        return value.selecting()
    }
    private func snapshot() -> QuotaSnapshot {
        var value = QuotaSnapshot(generatedAt: date, providers: [source("codex", signature: "HanzQ", current: true), source("codex", signature: "Alice"), source("deepseek"), source("kimi")])
        var preferences = PlatformPreferences(); preferences.codexMultiAccount = true
        preferences.connectionOrder = value.providers.map(\.id)
        preferences.menuOrder = value.providers.map(\.id)
        value.platformPreferences = preferences; value.heroSelection = .pinned(providerID: "codex")
        return value
    }
    private func selected(_ value: QuotaSnapshot, provider: String?, account: String?, oldSource: String? = nil, oldMetric: [String]? = nil) -> ProviderQuota? {
        WidgetAccountSelection.provider(in: value, providerID: provider, accountID: account,
            legacySourceID: oldSource, legacyMetric: oldMetric, legacyProviderID: nil)
    }
    func testProviderListGroupsAccountsAndRetainsHeroAndCustomProviders() {
        var value = snapshot(); var custom = source("custom-api.test"); custom.displayName = "My API"; value.providers.append(custom)
        let choices = WidgetAccountSelection.providers(in: value)
        XCTAssertEqual(choices.map(\.id), [WidgetDisplaySelection.heroID, "codex", "deepseek", "kimi", "custom-api.test"])
        XCTAssertEqual(choices.map(\.title), ["Hero", "Codex", "DeepSeek", "Kimi", "My API"])
        XCTAssertEqual(WidgetAccountSelection.providers(in: nil).map(\.id), [WidgetDisplaySelection.heroID])
    }
    func testAccountChoicesAreStrictlyScopedAndRespectVisibility() {
        var value = snapshot()
        XCTAssertEqual(WidgetAccountSelection.accounts(in: value, providerID: "codex").compactMap { $0.account?.signature }, ["HanzQ", "Alice"])
        XCTAssertEqual(WidgetAccountSelection.accounts(in: value, providerID: "deepseek").map(\.id), ["deepseek"])
        XCTAssertTrue(WidgetAccountSelection.accounts(in: value, providerID: WidgetDisplaySelection.heroID).isEmpty)
        XCTAssertTrue(WidgetAccountSelection.accounts(in: value, providerID: nil).isEmpty)
        value.providers[1].displayPreference?.availableInWidgets = false
        XCTAssertEqual(WidgetAccountSelection.accounts(in: value, providerID: "codex").count, 1)
    }
    func testSwitchingCodexToDeepSeekCannotRenderCodexFromStaleAccount() {
        let value = snapshot()
        XCTAssertEqual(selected(value, provider: "deepseek", account: value.providers[0].id)?.id, "deepseek")
        XCTAssertEqual(selected(value, provider: "codex", account: "deepseek")?.health?.state, .unavailable)
        XCTAssertNil(selected(value, provider: "codex", account: "deepseek")?.primaryMeter)
    }
    func testChosenAccountUsesItsConfiguredPrimaryMetric() {
        var value = snapshot()
        let product = value.providers[1].activeProducts[0]
        let chosenMetric = product.meters.last!.id
        value.providers[1] = value.providers[1].selecting(meterID: chosenMetric)
        let old = [value.providers[0].id, value.providers[0].activeProducts[0].id, value.providers[0].activeProducts[0].meters[0].id]
        let result = selected(value, provider: "codex", account: value.providers[1].id, oldSource: "deepseek", oldMetric: old)
        XCTAssertEqual(result?.account?.signature, "Alice")
        XCTAssertEqual(result?.primaryMeter?.id, chosenMetric)
    }
    func testHeroIgnoresAnyStaleAccountAndLegacyMetric() {
        var value = snapshot()
        let result = selected(value, provider: WidgetDisplaySelection.heroID, account: "deepseek", oldSource: value.providers[1].id, oldMetric: ["wrong"])
        XCTAssertEqual(result?.id, value.hero?.id)
        value.heroSelection = .pinned(providerID: "deepseek")
        XCTAssertEqual(selected(value, provider: WidgetDisplaySelection.heroID, account: value.providers[1].id)?.id, "deepseek")
    }
    func testLegacyFamilyAndAccountMigrationPreserveInactiveFixedAccount() {
        let value = snapshot(), oldID = value.providers[1].id
        XCTAssertEqual(WidgetAccountSelection.migratedProviderID(in: value, sourceID: oldID, metric: nil, legacyProviderID: nil), "codex")
        XCTAssertEqual(WidgetAccountSelection.defaultAccount(in: value, providerID: "codex", legacySourceID: oldID, legacyMetric: nil)?.id, oldID)
        XCTAssertEqual(selected(value, provider: "codex", account: nil, oldSource: oldID)?.id, oldID)
        XCTAssertEqual(selected(value, provider: nil, account: nil, oldSource: oldID)?.id, oldID)
    }
    func testLegacyMetricOnlyAndProviderOnlyMigration() {
        let value = snapshot(), old = value.providers[1], product = old.activeProducts[0]
        let metric = [old.id, product.id, product.meters.last!.id]
        XCTAssertEqual(WidgetAccountSelection.migratedProviderID(in: value, sourceID: nil, metric: metric, legacyProviderID: nil), "codex")
        XCTAssertEqual(WidgetAccountSelection.defaultAccount(in: value, providerID: "codex", legacySourceID: nil, legacyMetric: metric)?.id, old.id)
        XCTAssertEqual(selected(value, provider: nil, account: nil, oldMetric: metric)?.primaryMeter?.id, product.meters.last!.id)
        XCTAssertEqual(WidgetAccountSelection.migratedProviderID(in: value, sourceID: nil, metric: nil, legacyProviderID: "deepseek"), "deepseek")
        XCTAssertEqual(WidgetAccountSelection.migratedProviderID(in: nil, sourceID: nil, metric: nil, legacyProviderID: nil), WidgetDisplaySelection.heroID)
    }
    func testDeletedOrHiddenAccountNeverMigratesToAnotherAccount() {
        var value = snapshot(); let removed = value.providers.remove(at: 1)
        XCTAssertNil(WidgetAccountSelection.defaultAccount(in: value, providerID: "codex", legacySourceID: removed.id, legacyMetric: nil))
        XCTAssertEqual(selected(value, provider: "codex", account: nil, oldSource: removed.id)?.health?.state, .unavailable)
        XCTAssertEqual(selected(value, provider: "codex", account: removed.id)?.health?.state, .unavailable)
        value.providers[0].displayPreference?.availableInWidgets = false
        XCTAssertEqual(selected(value, provider: "codex", account: value.providers[0].id)?.health?.state, .unavailable)
    }
    func testFirstUseChoosesCurrentAccountAndSupportsSingleAccountMode() {
        let value = snapshot()
        XCTAssertEqual(WidgetAccountSelection.defaultAccount(in: value, providerID: "codex", legacySourceID: nil, legacyMetric: nil)?.account?.signature, "HanzQ")
        let single = QuotaSnapshot(generatedAt: date, providers: [source("codex"), source("deepseek")])
        XCTAssertEqual(WidgetAccountSelection.accounts(in: single, providerID: "codex").map(\.id), ["codex"])
        XCTAssertEqual(selected(single, provider: "codex", account: nil)?.id, "codex")
    }
}

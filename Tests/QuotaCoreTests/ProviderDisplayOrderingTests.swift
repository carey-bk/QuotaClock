import XCTest
@testable import QuotaCore

final class ProviderDisplayOrderingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func product(_ provider: String, suffix: String = "quota", value: Decimal = 50, kind: MeterKind = .percentageQuota) -> ProductQuota {
        var result = ProductQuota(id: "\(provider).\(suffix)", providerID: provider, displayName: provider,
            meters: [Meter(id: suffix, displayName: suffix, kind: kind, value: value,
                           currency: kind == .balance ? "CNY" : nil, updatedAt: date, reliability: .officialPublicAPI)], at: date)
        result.health = ProviderHealth(state: .healthy, lastSuccess: date)
        return result
    }
    private func snapshot(autoHero: Bool = true) -> QuotaSnapshot {
        let products = ["a", "b", "c", "d"].map { product($0) }
        let providers = products.map { product in
            var value = ProviderQuota(id: product.providerID, displayName: product.providerID, planName: nil,
                                      limits: [], lastUpdated: date, quotaChangedAt: date)
            value.products = [product]
            return value.selecting()
        }
        var result = QuotaSnapshot(generatedAt: date, providers: providers)
        var preferences = PlatformPreferences()
        preferences.connectionOrder = ["a", "b", "c", "d"]
        preferences.enabledProducts = Set(products.map(\.id))
        preferences.providerDisplay = .init(autoHero: autoHero)
        // Old per-surface choices and old visibility flags must not override the new queue.
        preferences.surfaces = .init(menu: ["d"], hero: "d", secondary: ["b"])
        result.platformPreferences = preferences
        for i in result.providers.indices {
            var hidden = ProviderDisplayPreference(); hidden.menuBarVisible = false
            hidden.screenSaverVisible = false; hidden.availableInWidgets = false; hidden.heroEligible = false
            result.providers[i].displayPreference = hidden
        }
        return result
    }
    func testPreviewUsesCurrentSnapshotAndVisibilityDoesNotChangeHeroOrOrder() {
        let current = snapshot(autoHero: false)
        var prefs = current.platformPreferences!
        prefs.providerDisplay?.menuLimit = 4
        var hidden = ProviderDisplayPreference(); hidden.menuBarVisible = false; hidden.screenSaverVisible = false
        prefs.display["b"] = hidden
        let preview = MenuPreviewProjection.snapshot(current, platform: prefs)!
        XCTAssertEqual(preview.revision, current.revision)
        XCTAssertEqual(preview.generatedAt, current.generatedAt)
        XCTAssertEqual(preview.providers, current.providers)
        XCTAssertEqual(preview.hero?.id, current.hero?.id)
        XCTAssertEqual(preview.platformPreferences?.connectionOrder, current.platformPreferences?.connectionOrder)
        XCTAssertEqual(preview.forSurface(.menuBar).providers.map(\.id), ["a", "c", "d"])
        XCTAssertEqual(preview.saverSecondaryProviders(portrait: false).map(\.id), ["c", "d"])
        XCTAssertEqual(current.forSurface(.menuBar).providers.map(\.id), ["a", "b", "c"])
        XCTAssertNil(MenuPreviewProjection.snapshot(nil, platform: prefs))
    }
    func testAutoHeroOffUsesBaseOrderForMenuSaverAndHeroWidget() {
        var value = snapshot(autoHero: false)
        value.providers[2].quotaChangedAt = date.addingTimeInterval(100)
        XCTAssertEqual(value.hero?.id, "a")
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(value.forSurface(.screenSaver).providers.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(value.saverSecondaryProviders(portrait: false).map(\.id), ["b", "c"])
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.id, "a")
        XCTAssertEqual(MenuBarIndicator(snapshot: value).providerID, "a")
    }
    func testAutoHeroPromotesCAndPreservesRestAndWidgetAccountChoices() throws {
        var value = snapshot()
        value.providers[2].quotaChangedAt = date.addingTimeInterval(100)
        value.platformPreferences?.providerDisplay?.heroProviderID = "c"
        XCTAssertEqual(value.providersInDisplayOrder.map(\.id), ["c", "a", "b", "d"])
        XCTAssertEqual(value.platformPreferences?.connectionOrder, ["a", "b", "c", "d"])
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(value.forSurface(.screenSaver).hero?.id, "c")
        XCTAssertEqual(value.saverSecondaryProviders(portrait: false).map(\.id), ["a", "b"])
        XCTAssertEqual(value.saverSecondaryProviders(portrait: true).map(\.id), ["a"])
        XCTAssertEqual(value.forSurface(.widget).providers.map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: "d", metric: nil)?.id, "d")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.id, "c")
        XCTAssertEqual(MenuBarIndicator(snapshot: value).providerID, "c")
        let projected = try JSONDecoder().decode(QuotaSnapshot.self, from: SnapshotStore.encode(value.displayProjection()))
        XCTAssertEqual(projected.hero?.id, "c")
        XCTAssertEqual(projected.providersInDisplayOrder.map(\.id), ["c", "a", "b", "d"])
        value.platformPreferences?.providerDisplay?.autoHero = false
        XCTAssertEqual(value.hero?.id, "a")
        value.platformPreferences?.connectionOrder = ["d", "c", "b", "a"]
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ["d", "c", "b"])
    }
    func testCountsTiesEmptyAndMissingProvidersHaveStableResults() {
        var value = snapshot()
        XCTAssertEqual(value.hero?.id, "a") // Equal timestamps use the user's order.
        value.platformPreferences?.providerDisplay?.menuLimit = 1
        value.platformPreferences?.providerDisplay?.saverLimit = 2
        XCTAssertEqual(value.forSurface(.menuBar).providers.map(\.id), ["a"])
        XCTAssertEqual(value.forSurface(.screenSaver).providers.map(\.id), ["a", "b"])
        XCTAssertEqual(value.saverSecondaryProviders(portrait: false).map(\.id), ["b"])
        value.platformPreferences?.connectionOrder = ["removed", "b", "b", "a"]
        value.providers.removeAll { $0.id == "a" }
        XCTAssertEqual(value.providersInDisplayOrder.map(\.id), ["b", "c", "d"])
        value.providers = []
        XCTAssertNil(value.hero)
        XCTAssertTrue(value.forSurface(.screenSaver).providers.isEmpty)
        XCTAssertTrue(value.saverSecondaryProviders(portrait: false).isEmpty)
    }
    func testSelectedFamilyFollowsCurrentLoginAndNeverUsesLatestQuotaChange() {
        var value = snapshot(); value.providers = []
        for (i, name) in ["Work", "Personal"].enumerated() {
            let account = AccountPresentation(id: UUID(), signature: name, isCurrent: i == 0)
            var item = product("codex", suffix: "subscription.account.\(account.id.uuidString.lowercased())")
            item.account = account
            var provider = ProviderQuota(id: item.sourceID, displayName: "Codex", planName: nil, limits: [],
                                         lastUpdated: date, quotaChangedAt: date.addingTimeInterval(Double(i)))
            provider.products = [item]; provider.account = account
            value.providers.append(provider.selecting())
        }
        value.platformPreferences?.connectionOrder = value.providers.map(\.id)
        XCTAssertFalse(value.followsCurrentCodexAccount)
        XCTAssertEqual(value.hero?.account?.signature, "Work")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.account?.signature, "Work")
        value.providers[0].account?.isCurrent = false
        value.providers[1].account?.isCurrent = true
        for index in value.providers.indices { let account = value.providers[index].account; value.providers[index].products?[0].account = account }
        XCTAssertEqual(value.hero?.account?.signature, "Personal")
        XCTAssertEqual(value.forSurface(.menuBar).providers.first?.account?.signature, "Personal")
        XCTAssertEqual(WidgetDisplaySelection.provider(in: value, sourceID: WidgetDisplaySelection.heroID, metric: nil)?.account?.signature, "Personal")
        value.providers[1].account?.isCurrent = false
        XCTAssertNil(value.hero?.account)
        XCTAssertEqual(value.hero?.health?.state, .unavailable)
        value.platformPreferences?.providerDisplay?.autoHero = false
        XCTAssertEqual(value.hero?.account?.signature, "Work")
    }
    func testConfigurationDefaultsBoundsAndRoundTrip() throws {
        let defaults = try JSONDecoder().decode(ProviderDisplayConfiguration.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.autoHero)
        XCTAssertEqual(defaults.effectiveMenuLimit, 3)
        XCTAssertEqual(defaults.effectiveSaverLimit, 3)
        XCTAssertEqual(ProviderDisplayConfiguration(menuLimit: 0, saverLimit: 1).effectiveMenuLimit, 1)
        XCTAssertEqual(ProviderDisplayConfiguration(menuLimit: 0, saverLimit: 1).effectiveSaverLimit, 2)
        XCTAssertEqual(ProviderDisplayConfiguration(menuLimit: 100, saverLimit: 100).effectiveSaverLimit, 3)
        var preferences = try JSONDecoder().decode(PlatformPreferences.self, from: Data("{}".utf8))
        XCTAssertNil(preferences.providerDisplay) // The app migrates once after loading actual connections.
        preferences.providerDisplay = .init(autoHero: false, menuLimit: 2, saverLimit: 2, heroProviderID: "b")
        preferences.connectionOrder = ["b", "a"]
        let restored = try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored, preferences)
    }
    func testChangeDetectionIgnoresRefreshMetadataAndIncludesAllQuotaWindowsAndCurrencies() {
        var old = product("a")
        old.meters.append(Meter(id: "weekly", displayName: "Weekly", kind: .percentageQuota, value: 60,
                                updatedAt: date, reliability: .officialCLI))
        var new = old
        new.health = ProviderHealth(state: .stale)
        new.meters[0].updatedAt = .now; new.meters[0].resetAt = .now
        new.meters[0].displayName = "Renamed"; new.defaultMeterID = "weekly"
        new.usage = .init(totalTokens: 500); new.bankResetCount = 2
        XCTAssertFalse(ProviderRefreshCoordinator.quotaValuesChanged(old, new))
        new.meters[1].value = 59
        XCTAssertTrue(ProviderRefreshCoordinator.quotaValuesChanged(old, new))
        old = product("a", kind: .balance); new = old; new.meters[0].value = 49.99
        XCTAssertTrue(ProviderRefreshCoordinator.quotaValuesChanged(old, new))
        old = product("a", kind: .usage); new = old; new.meters[0].value = 99
        XCTAssertFalse(ProviderRefreshCoordinator.quotaValuesChanged(old, new))
    }
    func testQuotaChangesDoNotChangeChosenHeroAndSelectionSurvivesRestart() async throws {
        var existing = snapshot(autoHero: true)
        var b = existing.providers[1]
        let balance = product("b", suffix: "balance", value: 20, kind: .balance)
        b.products?.append(balance); existing.providers[1] = b
        var preferences = try XCTUnwrap(existing.platformPreferences)
        preferences.enabledProducts.insert(balance.id)
        let quotaAdapter = DisplayOrderAdapter(try XCTUnwrap(b.products?.first))
        let balanceAdapter = DisplayOrderAdapter(balance)
        let aAdapter = DisplayOrderAdapter(product("a"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("shared.json")), display: SnapshotStore(url: root.appendingPathComponent("display.json")))
        let coordinator = ProviderRefreshCoordinator(adapters: [aAdapter, quotaAdapter, balanceAdapter], publisher: writer, existing: existing, preferences: preferences)
        await coordinator.refresh(productID: balance.id) { _ in }
        var next = await coordinator.current()
        XCTAssertEqual(next.hero?.id, "a") // Successful polling with the same value cannot steal Hero.
        var updated = balance; updated.meters[0].value = 19
        await balanceAdapter.set(updated)
        await coordinator.refresh(productID: balance.id) { _ in }
        next = await coordinator.current()
        XCTAssertEqual(next.hero?.id, "a") // Even a real balance change cannot steal Hero.
        preferences.providerDisplay?.heroProviderID = "b"
        next = try await coordinator.configure(preferences)
        XCTAssertEqual(next.hero?.id, "b")
        let changedAt = try XCTUnwrap(next.hero?.quotaChangedAt)
        await coordinator.refresh(productID: "a.quota") { _ in }
        next = await coordinator.current()
        XCTAssertEqual(next.hero?.id, "b")
        XCTAssertEqual(next.hero?.quotaChangedAt, changedAt)
        await balanceAdapter.fail()
        await coordinator.refresh(productID: balance.id) { _ in }
        next = await coordinator.current()
        XCTAssertEqual(next.hero?.id, "b")
        XCTAssertEqual(next.hero?.quotaChangedAt, changedAt)
        let restarted = ProviderRefreshCoordinator(adapters: [aAdapter, quotaAdapter, balanceAdapter], publisher: writer, existing: try writer.shared.read(), preferences: preferences)
        next = try await restarted.configure(preferences)
        XCTAssertEqual(next.hero?.id, "b")
        XCTAssertEqual(try writer.display.read().hero?.id, "b")
        preferences.enabledProducts.remove(balance.id); preferences.enabledProducts.remove("b.quota")
        next = try await restarted.configure(preferences)
        XCTAssertEqual(next.hero?.id, "a")
        XCTAssertFalse(next.forSurface(.menuBar).providers.contains { $0.id == "b" })
    }
}

private actor DisplayOrderAdapter: ProductAdapter {
    nonisolated let descriptor: ProductDescriptor
    private var product: ProductQuota
    private var failing = false
    init(_ product: ProductQuota) {
        self.product = product
        descriptor = ProductDescriptor(id: product.id, providerID: product.providerID, displayName: product.displayName,
                                       reliability: .officialPublicAPI, connection: "fixture")
    }
    func set(_ value: ProductQuota) { product = value; failing = false }
    func fail() { failing = true }
    func fetchProduct(at date: Date) async throws -> ProductQuota {
        if failing { throw ProviderFetchError.authenticationRequired }
        return product
    }
}

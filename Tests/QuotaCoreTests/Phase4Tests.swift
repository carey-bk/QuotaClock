import XCTest
@testable import QuotaCore

final class Phase4Tests: XCTestCase {
    func testProviderReorderingPersistsAcrossSurfacesAndPreservesVisibility() throws {
        var prefs = PlatformPreferences()
        prefs.menuOrder = ["kimi", "codex", "kimi", "obsolete"]
        var visibility = ProviderDisplayPreference()
        visibility.menuBarVisible = false
        prefs.display["kimi"] = visibility
        prefs.enabledProducts = ["codex.subscription"]
        prefs.moveProvider("codex", to: "kimi")
        XCTAssertEqual(prefs.menuOrder.first, "codex")
        XCTAssertEqual(prefs.menuOrder, prefs.saverOrder)
        XCTAssertEqual(Set(prefs.menuOrder), Set(ProviderCatalog.providers.map(\.id)))
        XCTAssertEqual(prefs.menuOrder.count, ProviderCatalog.providers.count)
        XCTAssertFalse(prefs.preference("kimi").menuBarVisible)
        XCTAssertTrue(prefs.preference("kimi").screenSaverVisible)
        XCTAssertEqual(prefs.enabledProducts, ["codex.subscription"])
        let restored = try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(restored, prefs)
        let before = prefs
        prefs.moveProvider("unknown", to: "kimi")
        XCTAssertEqual(prefs, before)
    }
    private let date = Date(timeIntervalSince1970: 1_790_467_200)
    func testAllLanguagesPersistWithoutChangingExistingLanguageIDs() throws {
        XCTAssertEqual(AppLanguage.english.rawValue, "english")
        XCTAssertEqual(AppLanguage.chinese.rawValue, "chinese")
        XCTAssertEqual(AppLanguage.allCases.count, 6)
        for language in AppLanguage.allCases {
            var preferences = AmbientPreferences(); preferences.language = language
            preferences.selectSurfaceLanguage(SurfaceLanguageSelection(rawValue: language.rawValue)!)
            let decoded = try JSONDecoder().decode(AmbientPreferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded, preferences)
            XCTAssertEqual(decoded.effectiveWidgetLanguage, language)
        }
    }
    func testAppearanceDefaultsAndRoundTripPreserveLanguage() throws {
        let old = try JSONDecoder().decode(AmbientPreferences.self, from: Data("{\"language\":\"chinese\"}".utf8))
        XCTAssertEqual(old.appearance, .system)
        for appearance in AppAppearance.allCases {
            var settings = old; settings.appearance = appearance
            let restored = try JSONDecoder().decode(AmbientPreferences.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored, settings)
            XCTAssertEqual(restored.language, .chinese)
        }
    }
    func testMenuIndicatorRespectsMetricVisibilityAndMissingData() throws {
        var code = try KimiProvider.parse(fixture("Kimi/code.json"), at: date)
        var provider = ProviderQuota(id: "kimi", displayName: "Kimi", planName: nil, limits: [], lastUpdated: date)
        for value in [Decimal(0), 12, 100] {
            code.meters[0].value = value
            provider.products = [code]; provider = provider.selecting()
            let indicator = MenuBarIndicator(snapshot: QuotaSnapshot(generatedAt: date, providers: [provider]))
            XCTAssertEqual(indicator.fraction, NSDecimalNumber(decimal: value).doubleValue / 100)
            XCTAssertEqual(indicator.text, "\(value)%")
        }
        let api = try KimiAPIProvider.parse(fixture("Kimi/api.json"), at: date)
        provider.products = [code, api]; provider = provider.selecting(productID: api.id)
        let balance = MenuBarIndicator(snapshot: QuotaSnapshot(generatedAt: date, providers: [provider]))
        XCTAssertNil(balance.fraction); XCTAssertEqual(balance.text, "¥88.20")
        provider.displayPreference?.menuBarVisible = false
        XCTAssertEqual(MenuBarIndicator(snapshot: QuotaSnapshot(generatedAt: date, providers: [provider])).text, "—")
        XCTAssertNil(MenuBarIndicator(snapshot: nil).fraction)
    }
    private func fixture(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/\(path)"))
    }
    private func writer() -> SnapshotPublisher {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return SnapshotPublisher(shared: SnapshotStore(url: root.appendingPathComponent("shared.json")), display: SnapshotStore(url: root.appendingPathComponent("display.json")))
    }
    func testV1MigrationKeepsIDsMeasurementsDatesAndLanguage() async throws {
        var old = MockProvider.snapshot(at: date)
        for i in old.providers.indices { old.providers[i].health = ProviderHealth(state: .healthy, lastSuccess: date) }
        let decoded = try JSONDecoder().decode(QuotaSnapshot.self, from: SnapshotStore.encode(old))
        XCTAssertNil(decoded.providers[0].products)
        var prefs = PlatformPreferences(); prefs.codexMultiAccount = false; prefs.enabledProducts = ["codex.subscription", "claude-code.subscription"]
        let coordinator = ProviderRefreshCoordinator(adapters: [] as [any ProductAdapter], publisher: writer(), existing: decoded, preferences: prefs)
        let next = try await coordinator.configure(prefs)
        XCTAssertEqual(next.providers.first?.primaryMeter?.value, 85)
        XCTAssertEqual(next.providers.first?.quotaChangedAt, date)
        XCTAssertEqual(next.providers.first?.primaryLimit?.id, old.providers.first?.primaryLimit?.id)
        XCTAssertEqual(next.providers.first?.products?.first?.id, "codex.subscription")
        let legacyPrefs = try JSONDecoder().decode(AmbientPreferences.self, from: Data(#"{"language":"chinese","menuLanguage":"english"}"#.utf8))
        XCTAssertFalse(legacyPrefs.useAppLanguageForSurfaces)
        XCTAssertEqual(legacyPrefs.effectiveMenuLanguage, .english)
        var freshPrefs = AmbientPreferences(); freshPrefs.language = .chinese
        XCTAssertEqual(freshPrefs.effectiveMenuLanguage, .english)
    }
    func testPreferenceMigrationPreservesDisabledAndKeysNeverInSettings() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "provider.claude-code.enabled")
        let prefs = PlatformPreferences.load(defaults: defaults)
        XCTAssertEqual(prefs.enabledProducts, ["codex.subscription", "deepseek.api"])
        XCTAssertFalse(prefs.enabledProducts.contains("kimi.code"))
        try prefs.save(defaults: defaults)
        XCTAssertEqual(PlatformPreferences.load(defaults: defaults), prefs)
        XCTAssertNotEqual(CredentialIdentity(providerID: "kimi", productID: "kimi.code").account,
                          CredentialIdentity(providerID: "kimi", productID: "kimi.api").account)
        XCTAssertNotEqual(CredentialIdentity(providerID: "a:b", productID: "c").account,
                          CredentialIdentity(providerID: "a", productID: "b:c").account)
        XCTAssertNotEqual(CredentialIdentity(providerID: "kimi", productID: "kimi.api", profileID: "one").account,
                          CredentialIdentity(providerID: "kimi", productID: "kimi.api", profileID: "two").account)
    }
    func testSixKindsValidateWithoutInventedPercentages() throws {
        for kind in MeterKind.allCases {
            let meter = Meter(id: kind.rawValue, displayName: "Metric", kind: kind, value: kind == .percentageQuota ? 22 : 12450,
                              currency: kind == .balance || kind == .spend ? "CNY" : nil, updatedAt: date, reliability: .officialPublicAPI)
            XCTAssertNoThrow(try meter.validated())
            if kind != .percentageQuota { XCTAssertFalse(meter.formattedValue.contains("%")) }
        }
        var invalid = Meter(id: "bad", displayName: "Bad", kind: .percentageQuota, value: 101, updatedAt: date, reliability: .officialCLI)
        XCTAssertThrowsError(try invalid.validated())
        invalid.value = .nan; XCTAssertThrowsError(try invalid.validated())
        invalid.value = -1; XCTAssertThrowsError(try invalid.validated())
        invalid.value = 10; invalid.kind = .balance; XCTAssertThrowsError(try invalid.validated())
    }
    func testOfficialSourceFixturesAndOptionalWindows() throws {
        let glm = try GLMProvider.parse(fixture("GLM/coding-plan.json"), at: date)
        XCTAssertEqual(glm.meters.map(\.value), [78, 60])
        XCTAssertEqual(glm.meters[0].reliability, .providerSupportedUndocumented)
        XCTAssertNil(glm.meters[0].resetAt)
        let kimi = try KimiProvider.parse(fixture("Kimi/code.json"), at: date)
        XCTAssertEqual(kimi.meters.map(\.value), [68, 40])
        XCTAssertEqual(kimi.meters[0].displayName, "Current plan quota")
        XCTAssertFalse(kimi.meters[0].displayName.contains("Weekly"))
        XCTAssertEqual(kimi.meters[1].windowDuration, 18000)
        XCTAssertEqual(try KimiAPIProvider.parse(fixture("Kimi/api.json"), at: date).meters[0].currency, "CNY")
        XCTAssertEqual(try KimiAPIProvider.parse(fixture("Kimi/api.json"), at: date, international: true).meters[0].currency, "USD")
        let coding = try BailianProvider.parse(fixture("Bailian/coding-plan.json"), product: "coding-plan", at: date)
        XCTAssertEqual(coding.meters.map(\.value), [62, 50, 5])
        XCTAssertEqual(coding.meters[0].resetAt?.timeIntervalSince1970, 1790467200)
        let token = try BailianProvider.parse(fixture("Bailian/token-plan.json"), product: "token-plan", at: date)
        XCTAssertEqual(token.meters.map(\.value), [75, 60])
        XCTAssertTrue(token.meters.allSatisfy { $0.kind == .percentageQuota })
        let optional = Data(#"{"per5HourPercentage":0.5}"#.utf8)
        XCTAssertEqual(try BailianProvider.parse(optional, product: "token-plan", at: date).meters.count, 1)
    }
    func testSchemaDriftAndMalformedNeverBecomeZero() throws {
        for raw in ["{}", "not-json", #"{"limits":[{"type":"NEW_UNKNOWN","percentage":20}]}"#,
                    #"{"limits":[{"type":"TOKENS_LIMIT","percentage":true}]}"#,
                    #"{"limits":[{"type":"TOKENS_LIMIT","percentage":101}]}"#] {
            XCTAssertThrowsError(try GLMProvider.parse(Data(raw.utf8), at: date))
        }
        for raw in ["{}", #"{"usage":{"limit":100}}"#, #"{"usage":{"limit":0,"used":0}}"#,
                    #"{"usage":{"limit":100,"used":30,"remaining":50}}"#,
                    #"{"usage":{"limit":true,"used":0}}"#, #"{"usage":{"limit":100,"used":1,"resetTime":"yesterday"}}"#] {
            XCTAssertThrowsError(try KimiProvider.parse(Data(raw.utf8), at: date))
        }
        XCTAssertThrowsError(try KimiAPIProvider.parse(Data(#"{"code":0,"status":true,"data":{}}"#.utf8), at: date))
        XCTAssertThrowsError(try BailianProvider.parse(Data(#"{"per5Hour":{"usedQuota":10}}"#.utf8), product: "coding-plan", at: date))
        XCTAssertThrowsError(try BailianProvider.parse(Data(#"{"per5HourPercentage":50}"#.utf8), product: "token-plan", at: date))
        XCTAssertThrowsError(try BailianProvider.parse(Data("{}".utf8), product: "token-plan", at: date))
    }
    func testHTTPAdaptersFailureMatrixAndMissingCredential() async throws {
        for id in ["glm", "kimi", "api"] {
            for status in [200, 401, 403, 429, 500] {
                let payload = try fixture(id == "glm" ? "GLM/coding-plan.json" : id == "kimi" ? "Kimi/code.json" : "Kimi/api.json")
                let client = MatrixHTTP(data: payload, status: status)
                let adapter: any ProductAdapter
                switch id {
                case "glm": adapter = GLMProvider(credential: { "FIXTURE_SECRET" }, client: client)
                case "kimi": adapter = KimiProvider(credential: { "FIXTURE_SECRET" }, client: client)
                default: adapter = KimiAPIProvider(credential: { "FIXTURE_SECRET" }, client: client)
                }
                do { _ = try await adapter.fetchProduct(at: date); XCTAssertEqual(status, 200) }
                catch let error as ProviderFetchError {
                    XCTAssertEqual(error.healthState, status == 429 ? .rateLimited : status == 500 ? .unavailable : .authenticationRequired)
                }
            }
            for code in [URLError.timedOut, .notConnectedToInternet] {
                let client = MatrixHTTP(data: Data(), status: 200, error: code)
                let adapter: any ProductAdapter
                switch id {
                case "glm": adapter = GLMProvider(credential: { "FIXTURE_SECRET" }, client: client)
                case "kimi": adapter = KimiProvider(credential: { "FIXTURE_SECRET" }, client: client)
                default: adapter = KimiAPIProvider(credential: { "FIXTURE_SECRET" }, client: client)
                }
                do { _ = try await adapter.fetchProduct(at: date); XCTFail("Expected transport failure") }
                catch let error as ProviderFetchError { XCTAssertEqual(error.healthState, code == .timedOut ? .error : .unavailable) }
            }
        }
        let missing = GLMProvider(credential: { nil }, client: MatrixHTTP(data: Data(), status: 200))
        do { _ = try await missing.fetchProduct(at: date); XCTFail("Missing credential") }
        catch ProviderFetchError.authenticationRequired {}
        let malformed = KimiProvider(credential: { "FIXTURE_SECRET" }, client: MatrixHTTP(data: Data("{}".utf8), status: 200))
        do { _ = try await malformed.fetchProduct(at: date); XCTFail("Malformed data") }
        catch ProviderFetchError.invalidResponse {}
    }
    func testHybridPartialSuccessIndependentBackoffAndRecovery() async throws {
        let code = try KimiProvider.parse(fixture("Kimi/code.json"), at: date)
        let api = try KimiAPIProvider.parse(fixture("Kimi/api.json"), at: date)
        let codeAdapter = ProductSequence(code, errors: [nil, nil, nil, nil])
        let apiAdapter = ProductSequence(api, errors: [nil, .rateLimited, nil])
        var prefs = PlatformPreferences(); prefs.enabledProducts = [code.id, api.id]
        let output = writer()
        let c = ProviderRefreshCoordinator(adapters: [codeAdapter, apiAdapter], publisher: output, existing: nil, preferences: prefs)
        await c.refreshAll(manual: true) { _ in }
        let first = await c.current()
        XCTAssertEqual(first.providers.count, 1)
        XCTAssertEqual(first.hero?.selectedProduct?.id, "kimi.code")
        await c.refreshAll(manual: true) { _ in }
        let partial = await c.current()
        XCTAssertEqual(partial.hero?.health?.state, .healthy)
        XCTAssertEqual(partial.hero?.activeProducts.first { $0.id == api.id }?.health?.state, .stale)
        XCTAssertEqual(partial.hero?.activeProducts.first { $0.id == api.id }?.meters, api.meters)
        XCTAssertEqual(first.hero?.quotaChangedAt, partial.hero?.quotaChangedAt)
        await c.refreshAll(manual: false) { _ in }
        let apiCalls = await apiAdapter.calls, codeCalls = await codeAdapter.calls
        // Neither product is due yet: one is backed off, the other is within its preferred interval.
        XCTAssertEqual(apiCalls, 2); XCTAssertEqual(codeCalls, 2)
        let dueNow = await c.hasAutomaticRefreshDue()
        let dueLater = await c.hasAutomaticRefreshDue(at: Date().addingTimeInterval(61))
        XCTAssertFalse(dueNow)
        XCTAssertTrue(dueLater)
        await c.refreshAll(manual: true) { _ in }
        let recovered = await c.current()
        XCTAssertEqual(recovered.providers[0].activeProducts.first { $0.id == api.id }?.health?.state, .healthy)
        XCTAssertEqual(recovered.hero?.quotaChangedAt, first.hero?.quotaChangedAt)
        XCTAssertEqual(try output.shared.read().revision, try output.display.read().revision)
    }
    func testVisibilityOrderingPinnedFallbackAndDisabledFetch() async throws {
        let code = try KimiProvider.parse(fixture("Kimi/code.json"), at: date)
        let a = ProductSequence(code, errors: [nil])
        var prefs = PlatformPreferences(); prefs.enabledProducts = [code.id]
        let c = ProviderRefreshCoordinator(adapters: [a], publisher: writer(), existing: nil, preferences: prefs)
        await c.refreshAll(manual: true) { _ in }
        prefs.display["kimi"] = .init(); prefs.display["kimi"]?.menuBarVisible = false
        prefs.display["kimi"]?.availableInWidgets = false
        var snapshot = try await c.configure(prefs)
        XCTAssertTrue(snapshot.forSurface(.menuBar).providers.isEmpty)
        XCTAssertTrue(snapshot.forSurface(.widget).providers.isEmpty)
        XCTAssertEqual(snapshot.forSurface(.screenSaver).providers.count, 1)
        snapshot.heroSelection = .pinned(providerID: "hidden")
        XCTAssertTrue(snapshot.pinnedHeroUnavailable)
        XCTAssertEqual(snapshot.hero?.id, "kimi")
        prefs.display["kimi"]?.heroEligible = false
        snapshot = try await c.configure(prefs)
        XCTAssertNil(snapshot.hero)
        prefs.enabledProducts.removeAll(); _ = try await c.configure(prefs)
        await c.refreshAll(manual: true) { _ in }
        let calls = await a.calls, disabled = await c.current()
        XCTAssertEqual(calls, 1); XCTAssertTrue(disabled.providers.isEmpty)
    }
    func testPrimarySelectionAndPrivacyRoundTrip() async throws {
        let code = try KimiProvider.parse(fixture("Kimi/code.json"), at: date)
        let api = try KimiAPIProvider.parse(fixture("Kimi/api.json"), at: date)
        var prefs = PlatformPreferences(); prefs.enabledProducts = [code.id, api.id]
        let output = writer()
        let c = ProviderRefreshCoordinator(adapters: [ProductSequence(code, errors: [nil]), ProductSequence(api, errors: [nil])], publisher: output, existing: nil, preferences: prefs)
        await c.refreshAll(manual: true) { _ in }
        prefs.display["kimi"] = .init(); prefs.display["kimi"]?.primaryProductID = api.id
        prefs.display["kimi"]?.primaryMeterID = "balance.CNY"
        let result = try await c.configure(prefs)
        XCTAssertEqual(result.hero?.primaryMeter?.formattedValue, "¥88.20")
        XCTAssertTrue(result.hero?.limits.isEmpty == true)
        let json = String(decoding: try SnapshotStore.encode(result.displayProjection()), as: UTF8.self)
        for forbidden in ["FIXTURE_SECRET", "Authorization", "lastAttempt", "profileID", "windowDuration"] { XCTAssertFalse(json.contains(forbidden)) }
        let roundTrip = try output.shared.read()
        XCTAssertEqual(roundTrip.hero?.selectedProduct?.id, api.id)
        XCTAssertEqual(roundTrip.hero?.primaryMeter?.id, "balance.CNY")
        let chosen = result.providers[0].selecting(productID: code.id, meterID: "window.300.MINUTE")
        XCTAssertEqual(chosen.primaryMeter?.value, 40)
    }
    func testIdentityChangeClearsOnlyThatProductsCachedAccount() async throws {
        let code = try KimiProvider.parse(fixture("Kimi/code.json"), at: date)
        let api = try KimiAPIProvider.parse(fixture("Kimi/api.json"), at: date)
        var prefs = PlatformPreferences(); prefs.enabledProducts = [code.id, api.id]
        let output = writer()
        let c = ProviderRefreshCoordinator(adapters: [ProductSequence(code, errors: [nil]), ProductSequence(api, errors: [nil])],
                                          publisher: output, existing: nil, preferences: prefs)
        await c.refreshAll(manual: true) { _ in }
        let changed = await c.invalidate(api.id)
        XCTAssertEqual(changed?.providers.first?.activeProducts.map(\.id), [code.id])
        XCTAssertEqual(try output.shared.read().providers.first?.activeProducts.map(\.id), [code.id])
        XCTAssertEqual(try output.display.read().providers.first?.activeProducts.map(\.id), [code.id])
    }
    func testInvalidBailianProfilesAreRejectedBeforeLaunchingCLI() async throws {
        for profile in ["", "../default", "--help", "中文", String(repeating: "a", count: 65)] {
            do {
                _ = try await BailianCLITransport().usage(product: "coding-plan", profile: profile)
                XCTFail("Invalid profile should not launch a process")
            } catch ProviderFetchError.invalidResponse {}
        }
    }
    func testBailianMockCLIAndUnavailable() async throws {
        let data = try fixture("Bailian/coding-plan.json")
        let adapter = BailianProvider(product: "coding-plan", transport: MockCLI(data: data, error: nil))
        let product = try await adapter.fetchProduct(at: date)
        XCTAssertEqual(product.meters.count, 3)
        for error in [ProviderFetchError.authenticationRequired, .rateLimited, .timeout, .unavailable, .invalidResponse] {
            let bad = BailianProvider(product: "token-plan", transport: MockCLI(data: Data(), error: error))
            do { _ = try await bad.fetchProduct(at: date); XCTFail("Expected CLI failure") }
            catch let found as ProviderFetchError { XCTAssertEqual(found.healthState, error.healthState) }
        }
    }
}
private struct MatrixHTTP: ProviderHTTPClient {
    let data: Data
    let status: Int
    var error: URLError.Code? = nil
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        if let error { throw URLError(error) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor ProductSequence: ProductAdapter {
    nonisolated let descriptor: ProductDescriptor
    let value: ProductQuota
    var errors: [ProviderFetchError?]
    var calls = 0
    init(_ value: ProductQuota, errors: [ProviderFetchError?]) {
        self.value = value; self.errors = errors; descriptor = ProviderCatalog.product(value.id)
    }
    func fetchProduct(at date: Date) async throws -> ProductQuota {
        calls += 1
        let error = errors.isEmpty ? nil : errors.removeFirst()
        if let error { throw error }
        return value
    }
}
private struct MockCLI: ProductCLITransport {
    let data: Data
    let error: ProviderFetchError?
    func usage(product: String, profile: String) async throws -> Data {
        XCTAssertTrue(["coding-plan", "token-plan"].contains(product))
        if let error { throw error }
        return data
    }
}

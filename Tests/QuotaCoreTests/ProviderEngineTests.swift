import XCTest
@testable import QuotaCore

final class ProviderEngineTests: XCTestCase {
    private let definition = ProviderEngineCatalog.all.first { $0.id == "gemini" }!
    private func parse(_ body: String) throws -> ProductQuota {
        try ProviderEngineAdapter.parse(Data(body.utf8), definition: definition, at: Date(timeIntervalSince1970: 1_700_000_000))
    }
    func testRegistryPreservesAllPinnedIDsWithoutReplacingNativeProducts() {
        XCTAssertEqual(ProviderEngineCatalog.all.count, 100)
        XCTAssertEqual(Set(ProviderEngineCatalog.all.map(\.id)).count, 100)
        XCTAssertEqual(Set(ProviderCatalog.products.map(\.id)).count, ProviderCatalog.products.count)
        XCTAssertEqual(ProviderCatalog.product("codex.subscription").connection, "local")
        XCTAssertTrue(PlatformPreferences().enabledProducts.isEmpty)
        XCTAssertTrue(ProviderEngineCatalog.all.allSatisfy { $0.sources.contains("auto") })
    }
    func testWindowsLabelsCadenceAndOverage() throws {
        let result = try parse(#"[{"provider":"gemini","rateWindowLabels":{"primary":"Pro","secondary":"Flash"},"usage":{"updatedAt":"2026-10-10T08:00:00Z","primary":{"usedPercent":25,"windowMinutes":300},"secondary":{"usedPercent":125},"extraRateWindows":[{"id":"lite","title":"Flash Lite","usageKnown":true,"window":{"usedPercent":0}}]}}]"#)
        XCTAssertEqual(result.meters.map(\.value), [75, 0, 100])
        XCTAssertEqual(result.meters.map(\.displayName), ["Pro", "Flash", "Flash Lite"])
        XCTAssertEqual(result.meters.first?.windowDuration, 18000)
        XCTAssertNil(result.meters[1].windowDuration)
    }
    func testPlaceholderUnknownAndIdentityAreNotPublished() throws {
        let result = try parse(#"[{"provider":"gemini","account":"private@example.test","diagnostic":"secret","usage":{"primary":{"usedPercent":0,"isSyntheticPlaceholder":true},"secondary":{"usedPercent":50},"extraRateWindows":[{"id":"hidden","title":"hidden","usageKnown":false,"window":{"usedPercent":0}}],"identity":{"accountEmail":"private@example.test","loginMethod":"Pro"}}}]"#)
        XCTAssertEqual(result.meters.count, 1)
        XCTAssertEqual(result.planName, "Pro")
        let data = try JSONEncoder().encode(result)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private@"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
    }
    func testOnlyTypedDetailProgressBecomesQuota() throws {
        let result = try parse(#"[{"provider":"gemini","usage":{"details":[{"rows":[{"label":"Requests","value":"30 / 100","progress":{"used":30,"total":100}},{"label":"Balance","value":"$123.00"}]}]}}]"#)
        XCTAssertEqual(result.meters.count, 1)
        XCTAssertEqual(result.meters[0].value, 70)
        XCTAssertEqual(result.meters[0].displayName, "Requests")
    }
    func testBalancesSpendingAndCreditsStaySeparate() throws {
        let result = try parse(#"[{"provider":"gemini","usage":{"providerCost":{"used":12,"limit":50,"balance":3,"currencyCode":"USD"}},"credits":{"remaining":0,"balanceReadSucceeded":true},"resetCredits":{"available":2}}]"#)
        XCTAssertEqual(result.meters.map(\.kind), [.balance, .spend, .credits])
        XCTAssertEqual(result.meters.map(\.value), [3, 12, 0])
        XCTAssertNil(result.meters.last?.currency)
        XCTAssertEqual(result.bankResetCount, 2)
    }
    func testInvalidMissingCrossProviderAndDuplicateDataFailClosed() {
        for body in [
            #"[{"provider":"claude","usage":{"primary":{"usedPercent":1}}}]"#,
            #"[{"provider":"gemini","usage":{"primary":{"usedPercent":true}}}]"#,
            #"[{"provider":"gemini","usage":{"primary":{"usedPercent":-1}}}]"#,
            #"[{"provider":"gemini","usage":{"primary":{"usedPercent":2,"windowMinutes":0}}}]"#,
            #"[{"provider":"gemini","usage":{}}]"#,
            #"[{"provider":"gemini","error":{"code":4},"usage":{"primary":{"usedPercent":1}}}]"#,
            #"[{"provider":"gemini","credits":{"remaining":0,"balanceReadSucceeded":false}}]"#,
            #"[{"provider":"gemini","usage":{"extraRateWindows":[{"id":"a","title":"A","window":{"usedPercent":1}},{"id":"a","title":"A","window":{"usedPercent":2}}]}}]"#
        ] { XCTAssertThrowsError(try parse(body), body) }
    }
    func testProcessBoundsTimeoutAndNonzeroOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fixture")
        func execute(_ body: String, timeout: TimeInterval = 1) throws -> Data {
            try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            return try BundledProviderEngine.run(provider: "gemini", config: root.appendingPathComponent("config.json"),
                cancellation: ProcessCancellation(), executableURL: script, timeout: timeout)
        }
        XCTAssertEqual(try execute("printf '[]'"), Data("[]".utf8))
        XCTAssertThrowsError(try execute("printf '[]'; exit 1"))
        XCTAssertThrowsError(try execute("exec /usr/bin/yes quota-fixture"))
        XCTAssertThrowsError(try execute("exec /bin/sleep 5", timeout: 0.1)) { error in
            if case ProviderFetchError.timeout = error {} else { XCTFail("Expected timeout") }
        }
        let cancellation = ProcessCancellation(); cancellation.cancel()
        XCTAssertThrowsError(try BundledProviderEngine.run(provider: "gemini", config: root, cancellation: cancellation, executableURL: script)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
    func testIsolatedConfigurationDefaultsRoundTripAndPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = try ProviderEngineConfiguration.load("gemini", root: root)
        XCTAssertFalse(settings.automaticCookies)
        settings.apiKey = "fixture-only"
        try ProviderEngineConfiguration.save(settings, provider: "gemini", root: root)
        XCTAssertEqual(try ProviderEngineConfiguration.load("gemini", root: root), settings)
        let url = try ProviderEngineConfiguration.url("gemini", root: root)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        settings.apiKey = "replacement"
        try ProviderEngineConfiguration.save(settings, provider: "gemini", root: root)
        XCTAssertEqual(try ProviderEngineConfiguration.load("gemini", root: root).apiKey, "replacement")
        XCTAssertThrowsError(try ProviderEngineConfiguration.url("../codex", root: root))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rows = try XCTUnwrap(json["providers"] as? [[String: Any]])
        rows[0]["workspaceExtra"] = "preserved"
        json["providers"] = rows
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        settings.apiKey = ""
        try ProviderEngineConfiguration.save(settings, provider: "gemini", root: root)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let savedRow = try XCTUnwrap((saved["providers"] as? [[String: Any]])?.first)
        XCTAssertEqual(savedRow["workspaceExtra"] as? String, "preserved")
        XCTAssertNil(savedRow["apiKey"])
        try Data("bad".utf8).write(to: url)
        XCTAssertThrowsError(try ProviderEngineConfiguration.load("gemini", root: root))
        XCTAssertThrowsError(try ProviderEngineConfiguration.save(settings, provider: "gemini", root: root))
    }
}

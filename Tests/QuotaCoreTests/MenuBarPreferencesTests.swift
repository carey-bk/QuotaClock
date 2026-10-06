import XCTest
@testable import QuotaCore

final class MenuBarPreferencesTests: XCTestCase {
    func testLargeHeroDefaultsOffAndPersistsWithoutChangingConnections() throws {
        let data = Data(#"{"enabledProducts":["deepseek.api"],"connectionOrder":["deepseek"],"menuBarIconStyle":"provider"}"#.utf8)
        var prefs = try JSONDecoder().decode(PlatformPreferences.self, from: data)
        XCTAssertFalse(prefs.menuBarHeroLarge)
        let suite = "MenuBarPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for enabled in [true, false] {
            prefs.menuBarHeroLarge = enabled
            try prefs.save(defaults: defaults)
            let restored = PlatformPreferences.load(defaults: defaults)
            XCTAssertEqual(restored, prefs)
            XCTAssertEqual(restored.enabledProducts, ["deepseek.api"])
            XCTAssertEqual(restored.connectionOrder, ["deepseek"])
            XCTAssertEqual(restored.menuBarIconStyle, .provider)
        }
    }
    func testLogoPreferenceDefaultsAndPersists() throws {
        let legacy = try JSONDecoder().decode(PlatformPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.appLogo, .classic)
        var preferences = legacy
        preferences.appLogo = .glow
        let restored = try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.appLogo, .glow)
        XCTAssertEqual(restored.enabledProducts, legacy.enabledProducts)
    }
    func testMissingIconSettingDefaultsToGaugeWithoutLosingConnections() throws {
        let data = Data(#"{"enabledProducts":["deepseek.api"],"connectionOrder":["deepseek"],"showMenuBar":false}"#.utf8)
        let prefs = try JSONDecoder().decode(PlatformPreferences.self, from: data)
        XCTAssertEqual(prefs.menuBarIconStyle, .clock)
        XCTAssertTrue(prefs.menuBarShowValue)
        XCTAssertFalse(prefs.showMenuBar)
        XCTAssertEqual(prefs.connectionOrder, ["deepseek"])
        XCTAssertEqual(prefs.enabledProducts, ["deepseek.api"])
    }
    func testUnconfiguredIconFallbackDoesNotEraseProviderPreference() {
        var prefs = PlatformPreferences()
        XCTAssertEqual(prefs.menuBarIconStyle, .clock)
        prefs.menuBarIconStyle = .provider
        XCTAssertEqual(prefs.effectiveMenuBarIconStyle(hasConfiguredProviders: false), .clock)
        XCTAssertEqual(prefs.effectiveMenuBarIconStyle(hasConfiguredProviders: true), .provider)
        prefs.menuBarIconStyle = .clock
        XCTAssertEqual(prefs.effectiveMenuBarIconStyle(hasConfiguredProviders: true), .clock)
    }
    func testPositionAlignmentAndScreenClamping() throws {
        let positions = MenuBarAlignment.allCases.map { $0.origin(anchorMin: 500, anchorMax: 540, width: 372, screenMin: 0, screenMax: 1200) }
        XCTAssertEqual(positions, [168, 334, 500])
        XCTAssertEqual(MenuBarAlignment.right.origin(anchorMin: 1190, anchorMax: 1210, width: 372, screenMin: 0, screenMax: 1200), 824)
        XCTAssertEqual(MenuBarAlignment.left.origin(anchorMin: -1450, anchorMax: -1430, width: 372, screenMin: -1500, screenMax: 0), -1496)
        for position in MenuBarAlignment.allCases {
            var prefs = PlatformPreferences(); prefs.menuBarAlignment = position; prefs.menuBarGaugeColor = .color
            XCTAssertEqual(try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(prefs)), prefs)
        }
    }
    func testAccountMenuEligibilityUsesLoginNotHeroOrEnabledState() {
        let current = ProviderAccount(signature: "Current", identityKey: "one", connection: .independent)
        var target = ProviderAccount(signature: "Target", identityKey: "two", connection: .independent)
        XCTAssertTrue(current.switchOption(currentIdentity: "one").isCurrent)
        XCTAssertFalse(current.switchOption(currentIdentity: "one").canSwitch)
        XCTAssertTrue(target.switchOption(currentIdentity: "one").canSwitch)
        target.credentialsHandedToCodex = true
        XCTAssertFalse(target.switchOption(currentIdentity: "one").canSwitch)
        target.credentialsHandedToCodex = nil; target.connection = .currentSession
        XCTAssertFalse(target.switchOption(currentIdentity: "one").canSwitch)
    }
    func testIconAndValueChoicesPersistIndependently() throws {
        for icon in MenuBarIconStyle.allCases {
            for showValue in [true, false] {
                var prefs = PlatformPreferences()
                prefs.menuBarIconStyle = icon; prefs.menuBarShowValue = showValue
                let restored = try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(prefs))
                XCTAssertEqual(restored, prefs)
            }
        }
    }
}

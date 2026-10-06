import XCTest
@testable import QuotaCore

final class SurfaceLanguageTests: XCTestCase {
    func testDefaultAndExplicitEnglishStayDistinctAndDoNotFollowApp() throws {
        var preferences = AmbientPreferences()
        preferences.language = .chinese
        XCTAssertEqual(preferences.displayedSurfaceLanguageSelection, .defaultEnglish)
        XCTAssertEqual(preferences.effectiveWidgetLanguage, .english)
        for choice in SurfaceLanguageSelection.allCases {
            preferences.selectSurfaceLanguage(choice)
            let decoded = try JSONDecoder().decode(AmbientPreferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded.displayedSurfaceLanguageSelection, choice)
            XCTAssertEqual(decoded.effectiveWidgetLanguage, choice.resolved(appLanguage: .chinese))
            XCTAssertEqual(decoded.effectiveMenuLanguage, decoded.effectiveWidgetLanguage)
            XCTAssertEqual(decoded.effectiveSaverLanguage, decoded.effectiveWidgetLanguage)
        }
    }
    func testOnlyFollowAppChangesWhenAppLanguageChanges() {
        var preferences = AmbientPreferences()
        preferences.selectSurfaceLanguage(.appLanguage)
        preferences.language = .traditionalChinese
        XCTAssertEqual(preferences.effectiveWidgetLanguage, .traditionalChinese)
        preferences.language = .french
        XCTAssertEqual(preferences.effectiveMenuLanguage, .french)
        preferences.selectSurfaceLanguage(.japanese)
        preferences.language = .korean
        XCTAssertEqual(preferences.effectiveWidgetLanguage, .japanese)
        XCTAssertEqual(preferences.effectiveSaverLanguage, .japanese)
    }
    func testLegacyLinkedUniformAndMixedLanguagesSurviveMigration() throws {
        func decode(_ json: String) throws -> AmbientPreferences {
            try JSONDecoder().decode(AmbientPreferences.self, from: Data(json.utf8))
        }
        let linked = try decode(#"{"language":"chinese","useAppLanguageForSurfaces":true}"#)
        XCTAssertEqual(linked.displayedSurfaceLanguageSelection, .appLanguage)
        XCTAssertEqual(linked.effectiveWidgetLanguage, .chinese)
        let uniform = try decode(#"{"language":"chinese","widgetLanguage":"french","menuLanguage":"french","saverLanguage":"french"}"#)
        XCTAssertEqual(uniform.displayedSurfaceLanguageSelection, .french)
        XCTAssertEqual(uniform.effectiveSaverLanguage, .french)
        var mixed = try decode(#"{"language":"chinese","widgetLanguage":"french","menuLanguage":"english","saverLanguage":"japanese"}"#)
        XCTAssertNil(mixed.displayedSurfaceLanguageSelection)
        mixed = try JSONDecoder().decode(AmbientPreferences.self, from: JSONEncoder().encode(mixed))
        XCTAssertEqual(mixed.effectiveWidgetLanguage, .french)
        XCTAssertEqual(mixed.effectiveMenuLanguage, .english)
        XCTAssertEqual(mixed.effectiveSaverLanguage, .japanese)
        mixed.selectSurfaceLanguage(.defaultEnglish)
        XCTAssertEqual(mixed.effectiveWidgetLanguage, .english)
        XCTAssertEqual(mixed.effectiveMenuLanguage, .english)
        XCTAssertEqual(mixed.effectiveSaverLanguage, .english)
    }
}

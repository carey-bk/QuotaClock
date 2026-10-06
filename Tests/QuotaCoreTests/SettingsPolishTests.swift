import XCTest
@testable import QuotaCore

final class SettingsPolishTests: XCTestCase {
    func testFreshDefaultsAndExplicitAlignmentMigration() throws {
        let fresh = try JSONDecoder().decode(PlatformPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(fresh.menuBarAlignment, .center)
        XCTAssertEqual(fresh.refreshPreference, .automaticOneMinute)
        let existing = try JSONDecoder().decode(PlatformPreferences.self, from: Data(#"{"menuBarAlignment":"left"}"#.utf8))
        XCTAssertEqual(existing.menuBarAlignment, .left)
        for choice in RefreshPreference.allCases {
            var p = fresh; p.refreshPreference = choice
            XCTAssertEqual(try JSONDecoder().decode(PlatformPreferences.self, from: JSONEncoder().encode(p)), p)
        }
        XCTAssertEqual(RefreshPreference.allCases.map(\.interval), [30, 60, 120, 300])
    }
    func testScheduleHonorsPreferenceMinimumAndBackoff() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(RefreshPreference.thirtySeconds.nextRefresh(after: start, minimum: 90, retryAfter: nil), start.addingTimeInterval(90))
        XCTAssertEqual(RefreshPreference.fiveMinutes.nextRefresh(after: start, minimum: 30, retryAfter: start.addingTimeInterval(60)), start.addingTimeInterval(300))
        XCTAssertEqual(RefreshPreference.twoMinutes.nextRefresh(after: start, minimum: 30, retryAfter: start.addingTimeInterval(600)), start.addingTimeInterval(600))
        XCTAssertEqual(RefreshPreference.thirtySeconds.nextRefresh(after: start, minimum: 30, retryAfter: .distantFuture), .distantFuture)
    }
    func testSurfaceDefaultsMigrationAndFollowRestoresIndependentChoices() throws {
        var p = try JSONDecoder().decode(AmbientPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(p.followsAppLanguage)
        XCTAssertEqual([p.effectiveWidgetLanguage, p.effectiveMenuLanguage, p.effectiveSaverLanguage], [.english, .english, .english])
        p = try JSONDecoder().decode(AmbientPreferences.self, from: Data(#"{"widgetLanguage":"japanese","menuLanguage":"chinese","saverLanguage":"french"}"#.utf8))
        p.language = .korean
        p.setFollowAppLanguage(true)
        XCTAssertEqual([p.effectiveWidgetLanguage, p.effectiveMenuLanguage, p.effectiveSaverLanguage], [.korean, .korean, .korean])
        p = try JSONDecoder().decode(AmbientPreferences.self, from: JSONEncoder().encode(p))
        p.setFollowAppLanguage(false)
        XCTAssertEqual([p.effectiveWidgetLanguage, p.effectiveMenuLanguage, p.effectiveSaverLanguage], [.japanese, .chinese, .french])
        p.selectSurfaceLanguage(.japanese)
        p.setLanguage(.french, for: .menuBar)
        XCTAssertEqual([p.effectiveWidgetLanguage, p.effectiveMenuLanguage, p.effectiveSaverLanguage], [.japanese, .french, .japanese])
    }
    func testFourCardsAndLargeHeroRemainScrollableOnShortScreen() {
        let layout = MenuPanelLayout(anchor: CGRect(x: 500, y: 780, width: 30, height: 20), screen: CGRect(x: 0, y: 0, width: 1200, height: 800), alignment: .center, cards: 4, accounts: 4, feedback: true, choosingAccount: false, largeHero: true)
        XCTAssertLessThan(layout.cardHeight, MenuCardLayout.contentHeight(cards: 4, largeHero: true))
        XCTAssertGreaterThanOrEqual(layout.main.minY, 4)
        XCTAssertLessThan(layout.main.maxY, 780)
        XCTAssertGreaterThanOrEqual(layout.main.height - layout.cardHeight, 102)
    }
}

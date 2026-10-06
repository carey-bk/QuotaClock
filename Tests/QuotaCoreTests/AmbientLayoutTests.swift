import XCTest
@testable import QuotaCore

final class AmbientLayoutTests: XCTestCase {
    func testScreenFamiliesCapVisibleCards() {
        for (w, h) in [(1920.0,1080.0),(2560,1600),(3024,1964),(3440,1440),(5120,1440),(1080,1920),(1440,2560),(1024,768)] {
            let result = AmbientLayoutEngine.layout(width: w, height: h, providerCount: 6)
            XCTAssertEqual(result.orientation, h > w * 1.15 ? .portrait : .landscape)
            XCTAssertGreaterThan(result.hero.width, 0)
            XCTAssertGreaterThan(result.hero.height, 0)
            XCTAssertNotNil(result.rail)
            XCTAssertGreaterThan(result.itemsPerPage, 0)
            XCTAssertGreaterThanOrEqual(result.pageCount, 1)
            XCTAssertLessThanOrEqual(result.hero.x + result.hero.width, w + 0.01)
            XCTAssertLessThanOrEqual(result.rail!.y + result.rail!.height, h + 0.01)
        }
        let wide = AmbientLayoutEngine.layout(width: 5120, height: 1440, providerCount: 3)
        XCTAssertLessThanOrEqual(wide.hero.width, 940)
        XCTAssertGreaterThan(wide.hero.width, wide.rail!.width)
        XCTAssertLessThanOrEqual(wide.hero.width / wide.hero.height, 1.25)
        let small = AmbientLayoutEngine.layout(width: 430, height: 280, providerCount: 6, preview: true)
        XCTAssertNil(small.rail)
        XCTAssertTrue(small.preview)
        let narrowPortrait = AmbientLayoutEngine.layout(width: 540, height: 960, providerCount: 4)
        XCTAssertFalse(narrowPortrait.preview)
        XCTAssertNotNil(narrowPortrait.rail)
        let singlePortrait = AmbientLayoutEngine.layout(width: 540, height: 960, providerCount: 1)
        XCTAssertEqual(singlePortrait.hero.width, singlePortrait.hero.height)
        XCTAssertLessThanOrEqual(singlePortrait.hero.y + singlePortrait.hero.height, 960)
        let crowded = AmbientLayoutEngine.layout(width: 1024, height: 768, providerCount: 20)
        XCTAssertEqual(crowded.pageCount, 1)
    }
    func testLandscapeClockAndBottomRailGeometry() {
        for (w, h) in [(1920.0, 1080.0), (2560, 1600), (3024, 1964)] {
            for count in [1, 2, 3, 6] {
                let layout = AmbientLayoutEngine.layout(width: w, height: h, providerCount: count)
                XCTAssertEqual(layout.hero.y + layout.hero.height / 2, h / 2, accuracy: 0.001)
                XCTAssertEqual(layout.itemsPerPage, count == 2 ? 1 : 2)
                let rail = layout.rail!
                XCTAssertEqual(rail.y + rail.height, layout.hero.y + layout.hero.height, accuracy: 0.001)
                XCTAssertGreaterThan(layout.clock.x, layout.hero.x + layout.hero.width)
                XCTAssertLessThan(layout.clock.y + layout.clock.height, rail.y)
                XCTAssertEqual(layout.pageCount, count == 1 ? 0 : 1)
            }
        }
    }
    func testPortraitReservesBothClockLinesAboveHero() {
        for (w, h) in [(540.0, 960.0), (1080, 1920), (1440, 2560)] {
            for count in [1, 2, 4] {
                let layout = AmbientLayoutEngine.layout(width: w, height: h, providerCount: count)
                XCTAssertGreaterThanOrEqual(layout.clock.height, layout.clock.width * 0.26)
                XCTAssertGreaterThan(layout.hero.y, layout.clock.y + layout.clock.height)
                XCTAssertLessThanOrEqual(layout.hero.y + layout.hero.height, h)
            }
        }
    }
    func testSingleSecondaryIsSquareAndEmptyRailKeepsHeroPosition() {
        for (w, h) in [(1920.0, 1080.0), (5120, 1440), (1080, 1920)] {
            let zero = AmbientLayoutEngine.layout(width: w, height: h, providerCount: 1)
            let one = AmbientLayoutEngine.layout(width: w, height: h, providerCount: 2)
            let two = AmbientLayoutEngine.layout(width: w, height: h, providerCount: 3)
            XCTAssertEqual(zero.hero, one.hero)
            XCTAssertEqual(one.hero, two.hero)
            XCTAssertEqual(zero.railDensity, .hidden)
            XCTAssertEqual(one.railDensity, .square)
            XCTAssertEqual(one.rail?.width, one.rail?.height)
            XCTAssertEqual(two.itemsPerPage, h > w * 1.15 ? 1 : 2)
            XCTAssertEqual(two.pageCount, 1)
        }
    }
    func testBurnInBounds() {
        for step in 0..<1000 {
            let point = AmbientLayoutEngine.burnInOffset(at: Date(timeIntervalSince1970: Double(step * 240)), enabled: true)
            XCTAssertLessThanOrEqual(abs(point.x), 8)
            XCTAssertLessThanOrEqual(abs(point.y), 8)
        }
        XCTAssertEqual(AmbientLayoutEngine.burnInOffset(at: .now, enabled: false).x, 0)
    }
    func testLanguageDefaultsAndTimeFormatting() {
        XCTAssertEqual(AmbientPreferences().language, .english)
        XCTAssertEqual(AmbientPreferences().widgetLanguage, .english)
        XCTAssertEqual(AmbientPreferences().menuLanguage, .english)
        XCTAssertEqual(AmbientPreferences().saverLanguage, .english)
        let older = Data(#"{"language":"chinese","showClock":false}"#.utf8)
        let migrated = try! JSONDecoder().decode(AmbientPreferences.self, from: older)
        XCTAssertEqual(migrated.language, .chinese)
        XCTAssertEqual(migrated.widgetLanguage, .english)
        XCTAssertEqual(migrated.menuLanguage, .english)
        XCTAssertEqual(migrated.saverLanguage, .english)
        XCTAssertFalse(migrated.showClock)
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(AmbientTimeText.time(date, format: .twentyFourHour).contains(":"))
        XCTAssertTrue(AmbientTimeText.time(date, format: .twelveHour, locale: Locale(identifier: "en_US")).contains("AM") ||
            AmbientTimeText.time(date, format: .twelveHour, locale: Locale(identifier: "en_US")).contains("PM"))
    }
}

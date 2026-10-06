import XCTest
@testable import QuotaCore

final class ScreenSaverSelectionTests: XCTestCase {
    private func store(_ path: String, provider: String = "com.apple.wallpaper.choice.screen-saver") throws -> Data {
        let configuration = try PropertyListSerialization.data(fromPropertyList: ["module": ["relative": path]], format: .binary, options: 0)
        return try PropertyListSerialization.data(fromPropertyList: ["AllSpacesAndDisplays": ["Idle": ["Content": ["Choices": [["Provider": provider, "Configuration": configuration]]]]]], format: .binary, options: 0)
    }
    func testRecognizesSystemWideSelectionWithEncodedPath() throws {
        XCTAssertEqual(ScreenSaverSelection.isQuotaClock(in: try store("file:///Library/Screen%20Savers/QuotaClock.saver")), true)
        XCTAssertEqual(ScreenSaverSelection.isQuotaClock(in: try store("file:///Library/Screen%20Savers/Fliqlo.saver")), false)
        XCTAssertEqual(ScreenSaverSelection.isQuotaClock(in: try store("file:///Library/Screen%20Savers/QuotaClock.saver", provider: "com.apple.wallpaper.choice.aerials")), false)
    }
    func testUnknownStateIsNotReportedAsEnabled() throws {
        XCTAssertNil(ScreenSaverSelection.isQuotaClock(in: Data()))
        let data = try PropertyListSerialization.data(fromPropertyList: ["SystemDefault": ["Idle": "unexpected"]], format: .binary, options: 0)
        XCTAssertNil(ScreenSaverSelection.isQuotaClock(in: data))
    }
}

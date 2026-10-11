import XCTest
@testable import QuotaCore

final class AppVersionTests: XCTestCase {
    func testNumericReleaseOrdering() {
        XCTAssertGreaterThan(AppVersion("v2.2.10")!, AppVersion("2.2.9")!)
        XCTAssertGreaterThan(AppVersion("3.0.0")!, AppVersion("2.99.99")!)
        XCTAssertLessThan(AppVersion("1.1.0")!, AppVersion("1.2.0-beta.12")!)
    }
    func testSameReleaseIgnoresInternalBuildAndPrerelease() {
        XCTAssertEqual(AppVersion("v1.2.0+20261010.161843"), AppVersion("1.2.0"))
        XCTAssertEqual(AppVersion("1.2.0-beta.12"), AppVersion("1.2.0"))
        XCTAssertEqual(AppVersion("1.2.0-beta.12")?.display, "v1.2.0")
    }
    func testLegacyAndInvalidVersions() {
        XCTAssertEqual(AppVersion("v1.0"), AppVersion("1.0.0"))
        for invalid in ["", "96", "20261010.161843.1234.5", "1.x.0", "1..0", "-1.2.3", "1.2.3.4"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
    }
}

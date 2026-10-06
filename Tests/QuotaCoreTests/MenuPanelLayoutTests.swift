import CoreGraphics
import XCTest
@testable import QuotaCore

final class MenuPanelLayoutTests: XCTestCase {
    func testLargeHeroUsesOneSquareWithoutShrinkingTheOtherCards() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 1100, y: 900, width: 30, height: 25)
        for count in 0...3 {
            let normal = MenuPanelLayout(anchor: anchor, screen: screen, alignment: .left, cards: count, accounts: 3,
                feedback: false, choosingAccount: false)
            let large = MenuPanelLayout(anchor: anchor, screen: screen, alignment: .left, cards: count, accounts: 3,
                feedback: false, choosingAccount: true, largeHero: true)
            XCTAssertEqual(large.cardHeight - normal.cardHeight, count == 0 ? 0 : 190)
            XCTAssertEqual(large.main.maxY, normal.main.maxY)
            XCTAssertEqual(large.main.width, normal.main.width)
            XCTAssertLessThan(large.chooser!.maxX, large.main.minX)
        }
        XCTAssertEqual(MenuCardLayout.height(large: true), MenuCardLayout.width)
        XCTAssertEqual(MenuCardLayout.height(large: false), 170)
    }
    func testLargeHeroScrollsOnShortDisplaysAndReservesNotificationRoom() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 600)
        let anchor = CGRect(x: 1000, y: 600, width: 30, height: 25)
        let normal = MenuPanelLayout(anchor: anchor, screen: screen, alignment: .left, cards: 3, accounts: 3,
            feedback: false, choosingAccount: false, largeHero: true)
        let message = MenuPanelLayout(anchor: anchor, screen: screen, alignment: .left, cards: 3, accounts: 3,
            feedback: true, choosingAccount: true, largeHero: true)
        XCTAssertGreaterThan(normal.cardHeight, MenuCardLayout.height(large: true))
        XCTAssertLessThan(normal.cardHeight, MenuCardLayout.contentHeight(cards: 3, largeHero: true))
        XCTAssertEqual(normal.cardHeight, message.cardHeight)
        XCTAssertEqual(message.main.height - normal.main.height, 48)
        XCTAssertEqual(message.main.maxY, normal.main.maxY)
        XCTAssertGreaterThanOrEqual(message.main.minY, 4)
    }
    func testChooserDoesNotConsumeCardsOrFooterHeight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let anchor = CGRect(x: 1100, y: 875, width: 30, height: 25)
        let closed = MenuPanelLayout(anchor: anchor, screen: screen, alignment: .left, cards: 3, accounts: 3, feedback: false, choosingAccount: false)
        let open = MenuPanelLayout(anchor: anchor, screen: screen, alignment: .left, cards: 3, accounts: 3, feedback: false, choosingAccount: true)
        XCTAssertEqual(closed.main, open.main)
        XCTAssertEqual(open.cardHeight, 546)
        XCTAssertLessThan(open.chooser!.maxX, open.main.minX)
        XCTAssertGreaterThanOrEqual(open.chooser!.minY, open.main.minY)
    }
    func testNotificationKeepsTopAndCardHeightAndMovesOnlyFooter() {
        for height in [600.0, 900] {
            let screen = CGRect(x: 0, y: 0, width: 1440, height: height)
            let a = CGRect(x: 1000, y: height, width: 40, height: 25)
            let before = MenuPanelLayout(anchor: a, screen: screen, alignment: .left, cards: 3, accounts: 3, feedback: false, choosingAccount: true)
            let after = MenuPanelLayout(anchor: a, screen: screen, alignment: .left, cards: 3, accounts: 3, feedback: true, choosingAccount: true)
            XCTAssertEqual(before.main.maxY, after.main.maxY)
            XCTAssertEqual(before.cardHeight, after.cardHeight)
            XCTAssertEqual(after.main.height - before.main.height, 48)
            XCTAssertGreaterThanOrEqual(after.main.minY, 4)
        }
    }
    func testChooserClampsAtLeftEdgeForAllAlignments() {
        let screen = CGRect(x: -1280, y: 0, width: 1280, height: 775)
        for alignment in MenuBarAlignment.allCases {
            let layout = MenuPanelLayout(anchor: CGRect(x: -1260, y: 775, width: 30, height: 25), screen: screen,
                alignment: alignment, cards: 3, accounts: 12, feedback: true, choosingAccount: true)
            XCTAssertGreaterThanOrEqual(layout.chooser!.minX, screen.minX + 4)
            XCTAssertLessThan(layout.chooser!.maxX, layout.main.minX)
            XCTAssertLessThanOrEqual(layout.main.maxX, screen.maxX - 4)
            XCTAssertEqual(layout.chooser!.height, 292)
        }
    }
}

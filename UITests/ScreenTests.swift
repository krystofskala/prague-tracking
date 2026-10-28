import XCTest

/// Walks through the main screen with the made-up demo walk (`-demo`, no
/// real location) and keeps a screenshot of every step for review.
final class ScreenTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ"]
    }

    func testMainScreenWithDemoWalk() {
        XCUIDevice.shared.appearance = .light
        app.launch()
        waitForDemoWalk()
        screenshot("1-mapa-s-dnesni-trasou")

        XCTAssertTrue(app.buttons["Zastavit"].exists, "demo walk shows tracking as on")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nahrávám trasu'")).firstMatch.exists)

        app.buttons["Úsporný"].tap()
        XCTAssertTrue(app.buttons["Úsporný"].isSelected)
        screenshot("2-usporny-rezim")
        app.buttons["Přesný"].tap()
        XCTAssertTrue(app.buttons["Přesný"].isSelected)

        app.buttons["Zastavit"].tap()
        XCTAssertTrue(app.buttons["Začít"].waitForExistence(timeout: 5))
        screenshot("3-sber-zastaven")
        app.buttons["Začít"].tap()

        app.buttons["Navrhni neprošlé ulice poblíž"].tap()
        XCTAssertTrue(app.navigationBars["Neprošlé ulice poblíž"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.cells.count, 0, "suggestions near the demo walk")
        screenshot("4-navrhy-neproslych-ulic")
        closeSheet()

        app.buttons["Procházky"].tap()
        XCTAssertTrue(app.navigationBars["Procházky"].waitForExistence(timeout: 10))
        let firstWalk = app.cells.firstMatch
        XCTAssertTrue(firstWalk.waitForExistence(timeout: 20), "the demo walk is listed")
        screenshot("5-seznam-prochazek")
        firstWalk.tap()
        XCTAssertTrue(app.staticTexts["Délka"].waitForExistence(timeout: 10))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "tiles")], timeout: 4)
        screenshot("6-detail-prochazky")
        closeSheet()

        app.buttons["Data"].tap()
        XCTAssertTrue(app.buttons["Vybrat složku v trezoru"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Importovat GPX…"].exists)
        screenshot("7-data-obsidian-zaloha-import")
        closeSheet()
    }

    private func closeSheet() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.staticTexts["pokryti"].waitForExistence(timeout: 10))
    }

    func testDarkMode() {
        XCUIDevice.shared.appearance = .dark
        app.launch()
        waitForDemoWalk()
        screenshot("8-tmavy-rezim")
        XCUIDevice.shared.appearance = .light
    }

    private func waitForDemoWalk() {
        let coverage = app.staticTexts["pokryti"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 30))
        // Streets load in a second or two, then the demo walk counts.
        let walked = NSPredicate(format: "NOT (label CONTAINS ' 0,0 %' OR label CONTAINS ' 0.0 %')")
        let done = expectation(for: walked, evaluatedWith: coverage)
        wait(for: [done], timeout: 90)
        // Map tiles.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "tiles")], timeout: 6)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

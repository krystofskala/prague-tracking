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
    }

    func testDarkMode() {
        XCUIDevice.shared.appearance = .dark
        app.launch()
        waitForDemoWalk()
        screenshot("5-tmavy-rezim")
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

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

        // E3: name, tag, colour.
        let name = app.textFields["nazev"]
        name.tap()
        name.typeText("Staré Město večer\n")
        let tag = app.textFields["novy-stitek"]
        tag.tap()
        tag.typeText("večer\n")
        app.buttons["Barva #af52de"].tap()
        XCTAssertTrue(app.buttons["#večer"].waitForExistence(timeout: 5))
        screenshot("6b-nazev-stitek-barva")

        app.buttons["Upravit trasu"].tap()
        XCTAssertTrue(app.navigationBars["Upravit trasu"].waitForExistence(timeout: 10))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "tiles")], timeout: 4)
        app.sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.15)
        screenshot("6c-oriznuti-zacatku")
        app.buttons["Smazat kus"].tap()
        app.sliders.element(boundBy: 1).adjust(toNormalizedSliderPosition: 0.6)
        app.sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.4)
        screenshot("6d-vyber-kusu-ke-smazani")
        app.buttons["Smazat vybraný kus"].tap()
        app.buttons["Dokreslit"].tap()
        screenshot("6e-dokreslit")
        app.buttons["Uložit"].tap()
        XCTAssertTrue(app.buttons["Vrátit původní trasu"].waitForExistence(timeout: 10))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "rebuild")], timeout: 3)
        screenshot("6f-upravena-prochazka")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Staré Město večer"].waitForExistence(timeout: 10))
        screenshot("6g-seznam-se-stitky")
        closeSheet()

        // Long press a street: "tenhle úsek jsem prošel".
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 1.2)
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "dialog")], timeout: 2)
        screenshot("6h-dlouhe-podrzeni-ulice")
        if app.buttons["Tenhle úsek jsem prošel"].exists {
            app.buttons["Tenhle úsek jsem prošel"].tap()
        } else if app.buttons["Zrušit"].exists {
            app.buttons["Zrušit"].tap()
        }

        // E5: overviews.
        app.buttons["Přehledy"].tap()
        XCTAssertTrue(app.navigationBars["Přehledy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Naplánuj procházku po neprošlých"].waitForExistence(timeout: 60), "stats computed from the log")
        screenshot("9a-neprosle-ulice")
        app.buttons["Naplánuj procházku po neprošlých"].tap()
        XCTAssertTrue(app.navigationBars["Plán procházky"].waitForExistence(timeout: 10))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "tiles")], timeout: 4)
        screenshot("9b-plan-prochazky")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Výzvy"].tap()
        app.switches.firstMatch.tap()
        app.buttons["Nová výzva"].tap()
        let challengeName = app.textFields["nazev-vyzvy"]
        XCTAssertTrue(challengeName.waitForExistence(timeout: 10))
        challengeName.tap()
        challengeName.typeText("Staré Město do Vánoc")
        screenshot("9c-nova-vyzva")
        app.buttons["Přidat"].tap()
        XCTAssertTrue(app.staticTexts["Staré Město do Vánoc"].waitForExistence(timeout: 10))
        screenshot("9d-vyzvy-a-mesicni-cil")

        app.buttons["Odznaky"].tap()
        XCTAssertTrue(app.staticTexts["První procházka"].waitForExistence(timeout: 10))
        screenshot("9e-odznaky")
        app.buttons["Čtvrti"].tap()
        screenshot("9f-ctvrti")
        app.buttons["Mapa"].tap()
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "tiles")], timeout: 4)
        screenshot("9g-heatmapa")
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
        app.launchArguments.append("-dark")
        app.launch()
        waitForDemoWalk()
        screenshot("8-tmavy-rezim")
    }

    private func waitForDemoWalk() {
        let coverage = app.staticTexts["pokryti"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 30))
        // Streets load in a second or two, then the demo walk counts.
        let walked = NSPredicate(format: "NOT (label CONTAINS ' 0,00 %' OR label CONTAINS ' 0.00 %')")
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

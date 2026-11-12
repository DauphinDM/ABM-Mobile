import XCTest

final class AppTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(invitation: String = "") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ABM_TEST_INVITATION"] = invitation
        app.launch()
        addUIInterruptionMonitor(withDescription: "Local network permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            return false
        }
        return app
    }
    func testNativeTabsAndOfflineSafety() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["pairPhone"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["pairPhone"].isEnabled)
        for name in ["Drive", "Car", "Garage", "Session", "Connect"] {
            app.tabBars.buttons[name].tap()
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3))
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Native \(name)"
            image.lifetime = .keepAlways; add(image)
        }
        app.tabBars.buttons["Car"].tap()
        app.swipeUp()
        let repair = app.buttons["repairVehicle"]
        XCTAssertTrue(repair.exists)
        XCTAssertFalse(repair.isEnabled)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Native Workshop — offline safety"
        image.lifetime = .keepAlways; add(image)
    }
    func testPinnedTlsGaragePhotoSpawnDirectApplyAndKeyboard() throws {
        guard let url = Bundle(for: Self.self).url(forResource: "TestConfig", withExtension: "json") else { throw XCTSkip("Run with the isolated local TLS fixture.") }
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: String]
        let app = launch(invitation: config["invitation"]!)
        let pair = app.buttons["pairPhone"]
        XCTAssertTrue(pair.waitForExistence(timeout: 10)); pair.tap()
        app.navigationBars.firstMatch.tap() // Deliver an interruption handler if iOS requests LAN permission.
        XCTAssertTrue(app.staticTexts["Paired with PC"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Garage"].tap()
        let model = app.buttons.containing(.staticText, identifier: "Fixture car").firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 10)); model.tap()
        let configuration = app.buttons.containing(.staticText, identifier: "Factory test").firstMatch
        XCTAssertTrue(configuration.waitForExistence(timeout: 10)); configuration.tap()
        XCTAssertTrue(app.images["vehiclePreview"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["spawn"].tap()
        XCTAssertFalse(app.buttons["confirmGameAction"].exists)
        app.tabBars.buttons["Car"].tap()
        XCTAssertTrue(app.navigationBars["Workshop"].waitForExistence(timeout: 5))
        let power = app.textFields["Power percent"]
        XCTAssertTrue(power.waitForExistence(timeout: 5)); power.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Exercise the software keyboard, including its dismissal toolbar.")
        power.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "200")
        XCTAssertEqual(power.value as? String, "200")
        let done = app.buttons["dismissKeyboard"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["power"].tap()
        XCTAssertFalse(app.buttons["confirmGameAction"].exists)
        app.swipeUp()
        let repair = app.buttons["repairVehicle"]
        XCTAssertTrue(repair.waitForExistence(timeout: 5)); XCTAssertTrue(repair.isEnabled)
        repair.tap()
        XCTAssertFalse(app.buttons["confirmGameAction"].exists)
        // Fixture stops snapshots after this command. The two-second watchdog must
        // clear telemetry and disable mutations rather than reconnect or queue.
        let disabled = NSPredicate(format: "enabled == false")
        expectation(for: disabled, evaluatedWith: repair)
        waitForExpectations(timeout: 8)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Stale connection disables native controls"
        image.lifetime = .keepAlways; add(image)
    }
}

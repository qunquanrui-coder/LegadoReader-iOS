import XCTest

final class SettingsSafetyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSupplementDefaultsPreservesCustomSource() {
        let app = launchFixture()
        openSettings(app)
        tapVisible(app.buttons["settings.sources.supplement"], in: app)
        dismissResult(app)
        assertCustomSource(app, exists: true)
    }

    func testResetRequiresConfirmationAndUndoRestoresOriginalSources() {
        let app = launchFixture()
        openSettings(app)
        tapVisible(app.buttons["settings.sources.reset"], in: app)
        let confirmation = app.alerts["完整重置全部书源？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["取消"].tap()
        assertCustomSource(app, exists: true)

        openSettings(app)
        tapVisible(app.buttons["settings.sources.reset"], in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["保存快照并重置"].tap()
        dismissResult(app)
        assertCustomSource(app, exists: false)

        openSettings(app)
        tapVisible(app.buttons["settings.sources.undoReset"], in: app)
        dismissResult(app)
        assertCustomSource(app, exists: true)
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        // Compiled only into Debug. This uses an isolated defaults suite and temporary cache.
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 15))
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        app.tabBars.buttons["我的"].tap()
    }

    private func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("The settings action must be reachable without hidden controls")
    }

    private func dismissResult(_ app: XCUIApplication) {
        let alert = app.alerts["备份与恢复提示"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["好的"].tap()
    }

    private func assertCustomSource(_ app: XCUIApplication, exists: Bool) {
        app.tabBars.buttons["书源"].tap()
        XCTAssertTrue(app.navigationBars["书源中心"].waitForExistence(timeout: 10))
        // The fixture inserts this source first; supplement and undo must preserve its row.
        let row = app.staticTexts["UI测试自定义源"].firstMatch
        if exists { XCTAssertTrue(row.waitForExistence(timeout: 10)) }
        else { XCTAssertFalse(row.waitForExistence(timeout: 2)) }
    }
}

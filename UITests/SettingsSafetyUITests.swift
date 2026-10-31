import XCTest

final class SettingsSafetyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSupplementDefaultsPreservesCustomSource() {
        let app = launchFixture()
        assertCustomSource(app, exists: true)
        tapButton(id: "settings.sources.supplement", title: "补充内置精选书源", in: app)
        dismissResult(app)
        assertCustomSource(app, exists: true)
    }

    func testResetRequiresConfirmationAndUndoRestoresOriginalSources() {
        let app = launchFixture()
        assertCustomSource(app, exists: true)
        tapButton(id: "settings.sources.reset", title: "完整重置书源…", in: app)
        let confirmation = app.alerts["完整重置全部书源？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["取消"].tap()
        assertCustomSource(app, exists: true)

        tapButton(id: "settings.sources.reset", title: "完整重置书源…", in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["保存快照并重置"].tap()
        dismissResult(app)
        assertCustomSource(app, exists: false)

        tapButton(id: "settings.sources.undoReset", title: "撤销上次书源重置", in: app)
        dismissResult(app)
        assertCustomSource(app, exists: true)
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        // Compiled only into Debug. This uses an isolated defaults suite and temporary cache.
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let supplementExists = app.buttons["settings.sources.supplement"].waitForExistence(timeout: 15)
            || app.buttons["补充内置精选书源"].waitForExistence(timeout: 5)
        XCTAssertTrue(supplementExists)
        return app
    }

    private func tapButton(id: String, title: String, in app: XCUIApplication) {
        let byID = app.buttons[id]
        let byTitle = app.buttons[title]
        if byID.waitForExistence(timeout: 5) && byID.isHittable {
            byID.tap()
            return
        }
        if byTitle.waitForExistence(timeout: 2) && byTitle.isHittable {
            byTitle.tap()
            return
        }
        for _ in 0..<6 {
            if byID.exists && byID.isHittable { byID.tap(); return }
            if byTitle.exists && byTitle.isHittable { byTitle.tap(); return }
            app.swipeUp()
        }
        XCTFail("The settings action \(id) (\(title)) must be reachable without hidden controls")
    }

    private func dismissResult(_ app: XCUIApplication) {
        let alert = app.alerts["备份与恢复提示"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["好的"].tap()
    }

    private func assertCustomSource(_ app: XCUIApplication, exists: Bool) {
        let predicate = NSPredicate(format: "label CONTAINS %@", "UI测试自定义源")
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        if exists {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
        } else {
            let disappeared = NSPredicate(format: "exists == false")
            let exp = expectation(for: disappeared, evaluatedWith: element)
            XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 10), .completed)
        }
    }
}

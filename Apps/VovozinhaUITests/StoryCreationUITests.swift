import XCTest

/// XCUITest coverage for story creation (host app).
final class StoryCreationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateStoryFromTenToTwentyWordSeed() throws {
        let app = XCUIApplication()
        app.launch()

        // Pin EN so scene labels are stable regardless of system language.
        let en = app.buttons["language.en"]
        if en.waitForExistence(timeout: 5) {
            en.tap()
        }

        // Model gate: create form only appears when Bonsai MLX pack is installed.
        try waitForCreateFormOrSkipIfModelMissing(in: app)

        let field = app.descendants(matching: .any)["storySeedField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "story seed field should appear")
        field.tap()

        let seed = "a little rabbit finds a glowing pebble under the soft moon light"
        field.typeText(seed)

        let create = app.buttons["createStoryButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: create, handler: nil)
        waitForExpectations(timeout: 3)

        create.tap()

        let result = app.descendants(matching: .any)["storyResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 120), "story result should appear after generation")

        XCTAssertTrue(
            app.staticTexts["Scene 1"].waitForExistence(timeout: 3)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Scene'")).firstMatch.exists
        )
    }

    func testLanguageBarVisibleOnModelGate() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["languageBar"].waitForExistence(timeout: 8))

        let pt = app.buttons["language.pt"]
        XCTAssertTrue(pt.waitForExistence(timeout: 5), "PT language control should exist")
        pt.tap()

        // Gate or create title should localize.
        let gateOrCreate =
            app.staticTexts["Modelo de história necessário"].waitForExistence(timeout: 4)
            || app.staticTexts["Descrição da história"].waitForExistence(timeout: 2)
            || app.buttons["Baixar modelo"].waitForExistence(timeout: 2)
            || app.buttons["Criar história"].waitForExistence(timeout: 2)
        XCTAssertTrue(gateOrCreate, "PT UI strings should appear on gate or create")
    }

    func testModelGateShowsDownloadWhenModelMissing() throws {
        let app = XCUIApplication()
        app.launch()

        let download = app.buttons["modelGateDownload"]
        let importBtn = app.buttons["modelGateImport"]
        let field = app.descendants(matching: .any)["storySeedField"]

        let appeared = download.waitForExistence(timeout: 10)
            || importBtn.waitForExistence(timeout: 2)
            || field.waitForExistence(timeout: 10)
        XCTAssertTrue(appeared, "either model gate or create form should appear")

        if download.exists {
            XCTAssertTrue(importBtn.exists, "import control should be on gate")
            XCTAssertTrue(app.buttons["modelGateOpenFallback"].exists)
            XCTAssertTrue(app.buttons["modelGateDecline"].exists)
        }
    }

    // MARK: - Helpers

    private func waitForCreateFormOrSkipIfModelMissing(in app: XCUIApplication) throws {
        let field = app.descendants(matching: .any)["storySeedField"]
        let download = app.buttons["modelGateDownload"]

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if field.exists { return }
            if download.exists {
                throw XCTSkip("Bonsai MLX model not installed; use Download model on device (Wi‑Fi)")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("timed out waiting for model gate or create form")
    }
}

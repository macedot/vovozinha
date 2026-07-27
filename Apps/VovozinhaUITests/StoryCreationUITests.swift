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

        // Seed field (SwiftUI TextField axis: .vertical often surfaces as TextView)
        let field = app.descendants(matching: .any)["storySeedField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "story seed field should appear")
        field.tap()

        let seed = "a little rabbit finds a glowing pebble under the soft moon light"
        // 12 words
        field.typeText(seed)

        let create = app.buttons["createStoryButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        // Button may need a moment for word-count validation to enable
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: create, handler: nil)
        waitForExpectations(timeout: 3)

        create.tap()

        let result = app.descendants(matching: .any)["storyResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 8), "story result should appear after generation")

        // Scene labels from the offline generator (EN)
        XCTAssertTrue(
            app.staticTexts["Scene 1"].waitForExistence(timeout: 3)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Scene'")).firstMatch.exists
        )
    }

    func testLanguageBarSwitchesUIToPortugueseAndSpanish() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["languageBar"].waitForExistence(timeout: 8))

        let pt = app.buttons["language.pt"]
        XCTAssertTrue(pt.waitForExistence(timeout: 5), "PT language control should exist")
        pt.tap()
        XCTAssertTrue(
            app.staticTexts["Descrição da história"].waitForExistence(timeout: 4)
                || app.buttons["Criar história"].waitForExistence(timeout: 2),
            "PT UI strings should appear"
        )

        let es = app.buttons["language.es"]
        XCTAssertTrue(es.waitForExistence(timeout: 3))
        es.tap()
        XCTAssertTrue(
            app.staticTexts["Descripción del cuento"].waitForExistence(timeout: 4)
                || app.buttons["Crear cuento"].waitForExistence(timeout: 2),
            "ES UI strings should appear"
        )

        let en = app.buttons["language.en"]
        en.tap()
        XCTAssertTrue(
            app.staticTexts["Story description"].waitForExistence(timeout: 4)
                || app.buttons["Create story"].waitForExistence(timeout: 2),
            "EN UI strings should appear"
        )
    }
}

import XCTest

/// CLI-driven story creation on Simulator (no manual Simulator.app required).
final class StoryCreationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateStoryFromTenToTwentyWordSeed() throws {
        let app = XCUIApplication()
        app.launch()

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

        // Scene labels from the offline generator
        XCTAssertTrue(
            app.staticTexts["Scene 1"].waitForExistence(timeout: 3)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Scene'")).firstMatch.exists
        )
    }
}

import XCTest
@testable import StoryPromptKit

final class StoryPromptKitTests: XCTestCase {
    func testWordCountBounds() {
        let short = StorySeedPrompt(text: "one two three")
        XCTAssertEqual(short.wordCount, 3)
        XCTAssertFalse(short.isValid)

        let ok = StorySeedPrompt(
            text: "a cozy forest friend helps a lost star find home at night"
        )
        XCTAssertEqual(ok.wordCount, 12)
        XCTAssertTrue(ok.isValid)

        let long = StorySeedPrompt(
            text: "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone"
        )
        XCTAssertGreaterThan(long.wordCount, StorySeedPrompt.maxWords)
        XCTAssertFalse(long.isValid)
    }

    func testOfflineGeneratorProducesTenScenes() async throws {
        let seed = StorySeedPrompt(
            text: "a little rabbit finds a glowing pebble under the moon and smiles"
        )
        XCTAssertTrue(seed.isValid)
        let draft = try await OfflineStoryFromPromptGenerator().generate(from: seed)
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertFalse(draft.title.isEmpty)
        XCTAssertTrue(draft.fullText.localizedCaseInsensitiveContains("pebble")
            || draft.summary.localizedCaseInsensitiveContains("rabbit")
            || draft.seedPrompt.localizedCaseInsensitiveContains("rabbit"))
    }

    func testGeneratorRejectsShortPrompt() async {
        let seed = StorySeedPrompt(text: "too short")
        do {
            _ = try await OfflineStoryFromPromptGenerator().generate(from: seed)
            XCTFail("expected validation error")
        } catch let e as StorySeedPrompt.ValidationError {
            if case .tooShort = e { /* ok */ } else { XCTFail("\(e)") }
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}

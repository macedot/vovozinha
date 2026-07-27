import XCTest
import os
@testable import StoryPromptKit
import VovoUI

// MARK: - Test helpers

/// Records the prompt it received and returns a canned reply, optionally throwing.
final class MockLiteRTLMEngineSession: LiteRTLMEngineSessioning, @unchecked Sendable {
    let reply: String
    let error: (any Error)?
    private let lastPrompt = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(reply: String, error: (any Error)? = nil) {
        self.reply = reply
        self.error = error
    }

    var capturedPrompt: String? { lastPrompt.withLock { $0 } }

    func send(_ prompt: String) async throws -> String {
        lastPrompt.withLock { $0 = prompt }
        if let error { throw error }
        return reply
    }
}

private func validSeed(
    _ text: String = "a little rabbit finds a glowing pebble under the soft moon light",
    language: AppLanguage = .englishUS
) -> StorySeedPrompt {
    StorySeedPrompt(text: text, language: language)
}

// MARK: - LiteRTLMStoryGenerator

final class LiteRTLMStoryGeneratorTests: XCTestCase {
    private static let wellFormedReply = """
    TITLE: The Glowing Pebble
    SUMMARY: A gentle bedtime tale about a curious rabbit.

    Evening light softens the world. A little rabbit hops along a quiet path and spots something glimmering near the mossy stones. It is a pebble, warm and faintly glowing, the color of sleepy sunshine.

    The rabbit tilts its head. The pebble hums a tiny, kind song, like a lullaby only the heart can hear. Curiosity tugs gently, not scary, just a soft wondering.

    A small problem appears, light enough for little hearts. The pebble is dimming, and the rabbit feels it might fade before morning comes.

    Feelings settle like warm blankets. There is a little worry, and a little courage, resting side by side under the silver sky.

    A kind plan takes shape. The rabbit decides to carry the pebble to the tallest hill, where the moon can share its light.

    The first careful try happens slowly. Small paws cradle the pebble, and a slow climb begins, one gentle step at a time.

    A friendly helper joins in. A sleepy owl shows a shorter path, and together the climb feels lighter and warmer.

    Things turn better. At the hilltop the moon smiles down, and the pebble glows bright again, full of soft golden light.

    The lesson shines without a lecture: kindness and care keep gentle things glowing, even in the quietest night.

    Night arrives softly. Stars wink like tiny lamps as the rabbit curls up, dreaming of warm pebbles and kind moons.
    """

    func testParsesWellFormedReplyIntoTenParagraphs() async throws {
        let session = MockLiteRTLMEngineSession(reply: Self.wellFormedReply)
        let gen = try LiteRTLMStoryGenerator(modelPath: "/ignored", cacheDir: "/tmp", session: session)
        let draft = try await gen.generate(from: validSeed())

        XCTAssertEqual(draft.title, "The Glowing Pebble")
        XCTAssertTrue(draft.summary.contains("gentle bedtime"))
        XCTAssertEqual(draft.paragraphs.count, 10, "contract: exactly 10 paragraphs")
        XCTAssertEqual(draft.language, .englishUS)
        XCTAssertFalse(draft.paragraphs.first?.isEmpty ?? true)
    }

    func testPromptIncludesSeedDescription() async throws {
        let session = MockLiteRTLMEngineSession(reply: Self.wellFormedReply)
        let gen = try LiteRTLMStoryGenerator(modelPath: "/ignored", cacheDir: "/tmp", session: session)
        let seedText = "a brave little boat sails across a calm silver lake"
        _ = try await gen.generate(from: validSeed(seedText))

        let prompt = try XCTUnwrap(session.capturedPrompt)
        XCTAssertTrue(prompt.contains(seedText), "seed should be injected into the LiteRT-LM prompt")
    }

    // Regression: the LiteRT-LM prompt must actually vary with the seed (i.e. we really use the
    // prompt, not a fixed string), and must never leak the raw INSERT placeholder.
    func testPromptVariesWithSeedAndCarriesEachSeed() {
        let boat = "a brave little boat sails across a calm silver lake"
        let bear = "a sleepy bear finds a glowing star in the winter forest"
        let promptBoat = LiteRTLMStoryGenerator.buildPrompt(seed: boat, language: .englishUS)
        let promptBear = LiteRTLMStoryGenerator.buildPrompt(seed: bear, language: .englishUS)

        XCTAssertNotEqual(promptBoat, promptBear, "different seeds must produce different prompts")
        XCTAssertTrue(promptBoat.contains(boat))
        XCTAssertTrue(promptBear.contains(bear))
        XCTAssertFalse(
            OfflineStoryFromPromptGenerator.containsUnresolvedDescriptionPlaceholder(promptBoat),
            "no INSERT placeholder should remain in the filled prompt"
        )
    }

    func testBuildPromptHasNoUnresolvedPlaceholdersForAllLanguages() {
        for lang in AppLanguage.allCases {
            let prompt = LiteRTLMStoryGenerator.buildPrompt(seed: "some seed text here", language: lang)
            XCTAssertFalse(prompt.isEmpty, lang.rawValue)
            XCTAssertFalse(
                OfflineStoryFromPromptGenerator.containsUnresolvedDescriptionPlaceholder(prompt),
                "unresolved placeholder for \(lang.rawValue)"
            )
        }
    }

    func testRejectsShortPrompt() async throws {
        let session = MockLiteRTLMEngineSession(reply: Self.wellFormedReply)
        let gen = try LiteRTLMStoryGenerator(modelPath: "/ignored", cacheDir: "/tmp", session: session)
        do {
            _ = try await gen.generate(from: StorySeedPrompt(text: "too short", language: .englishUS))
            XCTFail("expected validation error")
        } catch let e as StorySeedPrompt.ValidationError {
            if case .tooShort = e { /* ok */ } else { XCTFail("\(e)") }
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testNormalizeTruncatesToTenAndThrowsWhenTooFew() throws {
        // Fewer than 10 paragraphs is a generation failure — OfflineFirst falls back instead
        // of rendering empty scene cards.
        XCTAssertThrowsError(try LiteRTLMStoryGenerator.normalizeParagraphs("one\n\ntwo")) {
            XCTAssertEqual($0 as? StoryPromptError, .generationFailed)
        }

        let tooMany = try LiteRTLMStoryGenerator.normalizeParagraphs(
            (1...13).map { "p\($0)" }.joined(separator: "\n\n")
        )
        XCTAssertEqual(tooMany.count, 10)
        XCTAssertEqual(tooMany.last, "p10")

        let exactlyTen = try LiteRTLMStoryGenerator.normalizeParagraphs(
            (1...10).map { "p\($0)" }.joined(separator: "\n\n")
        )
        XCTAssertEqual(exactlyTen.count, 10)
    }

    func testParseRecoversWhenTitleHeaderMissing() throws {
        let body = (1...10)
            .map { "Scene \($0) text." }
            .joined(separator: "\n\n")
        let parsed = try LiteRTLMStoryGenerator.parse(body)
        XCTAssertEqual(parsed.paragraphs.count, 10)
        XCTAssertEqual(parsed.title, "Bedtime Story") // en-US default fallback title
        XCTAssertEqual(parsed.summary, "")
    }

    func testParseFallbackTitleIsLocalized() throws {
        let body = (1...10)
            .map { "Cena \($0) texto." }
            .joined(separator: "\n\n")
        let pt = try LiteRTLMStoryGenerator.parse(body, language: .portugueseBrazil)
        XCTAssertEqual(pt.title, "História de ninar")
        let es = try LiteRTLMStoryGenerator.parse(body, language: .spanishSpain)
        XCTAssertEqual(es.title, "Cuento de dormir")
    }

    func testParseThrowsWhenReplyHasTooFewParagraphs() {
        let body = """
        TITLE: Short Tale
        SUMMARY: Too short.

        Only one paragraph here.

        And another.
        """
        XCTAssertThrowsError(try LiteRTLMStoryGenerator.parse(body)) {
            XCTAssertEqual($0 as? StoryPromptError, .generationFailed)
        }
    }

    func testThrowsOnEmptyBody() {
        XCTAssertThrowsError(try LiteRTLMStoryGenerator.parse("   \n\n  "))
    }
}

// MARK: - OfflineFirstStoryGenerator

final class OfflineFirstStoryGeneratorTests: XCTestCase {
    func testFallsBackToOfflineWhenModelAbsent() async throws {
        // Point the store at a temp dir with no model file.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LiteRTLMModelStore(documentsURL: tmp)
        // Deterministic offline variants so the summary assertion is stable.
        let generator = OfflineFirstStoryGenerator(
            modelStore: store,
            offline: OfflineStoryFromPromptGenerator(pickVariant: { _ in 0 })
        )
        let draft = try await generator.generate(from: validSeed())

        // Offline generator output shape: 10 paragraphs + offline summary marker.
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertTrue(draft.summary.contains("bedtime"))
    }

    func testUsesLiteRTLMWhenModelPresentAndNeverThrowsOnInferenceError() async throws {
        // Simulate a "present" model by writing a non-empty file into the store's dir.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LiteRTLMModelStore(documentsURL: tmp)

        // Place a dummy non-empty file at the model path.
        let modelURL = await store.modelFileURL()
        try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x00, 0x01]).write(to: modelURL)
        let presentBefore = await store.isModelPresent()
        XCTAssertTrue(presentBefore)

        // Session that always errors → composite must fall back to offline, never throw.
        let failing = MockLiteRTLMEngineSession(reply: "", error: URLError(.cannotConnectToHost))
        let generator = OfflineFirstStoryGenerator(
            modelStore: store,
            offline: OfflineStoryFromPromptGenerator(pickVariant: { _ in 0 })
        ) { _, _ in failing }

        let draft = try await generator.generate(from: validSeed())
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertTrue(draft.summary.contains("bedtime"), "should be the offline fallback")
    }

    func testPropagatesValidationError() async throws {
        let store = LiteRTLMModelStore(documentsURL: FileManager.default.temporaryDirectory)
        let generator = OfflineFirstStoryGenerator(modelStore: store)
        do {
            _ = try await generator.generate(from: StorySeedPrompt(text: "x", language: .englishUS))
            XCTFail("expected validation error")
        } catch let e as StorySeedPrompt.ValidationError {
            if case .tooShort = e { /* ok */ } else { XCTFail("\(e)") }
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}

// MARK: - LiteRTLMModelStore

final class LiteRTLMModelStoreTests: XCTestCase {
    func testModelURLResolvesUnderVovozinhaModels() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LiteRTLMModelStore(documentsURL: tmp)
        let exp = expectation(description: "url")
        Task {
            let url = await store.modelFileURL()
            XCTAssertEqual(url.lastPathComponent, LiteRTLMModelStore.defaultModelFilename)
            XCTAssertTrue(url.path.contains("Vovozinha/Models"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testIsModelPresentReflectsFileExistence() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LiteRTLMModelStore(documentsURL: tmp)

        let absentInitially = await store.isModelPresent()
        XCTAssertFalse(absentInitially)

        let url = await store.modelFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x00]).write(to: url)
        let presentAfterWrite = await store.isModelPresent()
        XCTAssertTrue(presentAfterWrite)

        try await store.removeModel()
        let absentAfterRemove = await store.isModelPresent()
        XCTAssertFalse(absentAfterRemove)
    }
}

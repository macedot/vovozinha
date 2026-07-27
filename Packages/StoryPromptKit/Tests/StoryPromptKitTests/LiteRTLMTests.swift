import XCTest
import os
@testable import StoryPromptKit
import VovoUI

// MARK: - Test helpers

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
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertEqual(draft.title, "The Glowing Pebble")
    }

    func testPromptIncludesSeedDescription() async throws {
        let session = MockLiteRTLMEngineSession(reply: Self.wellFormedReply)
        let gen = try LiteRTLMStoryGenerator(modelPath: "/ignored", cacheDir: "/tmp", session: session)
        let seedText = "a brave little boat sails across a calm silver lake"
        _ = try await gen.generate(from: validSeed(seedText))
        XCTAssertTrue(try XCTUnwrap(session.capturedPrompt).contains(seedText))
    }

    func testNormalizeThrowsWhenTooFew() throws {
        XCTAssertThrowsError(try LiteRTLMStoryGenerator.normalizeParagraphs("one\n\ntwo")) {
            XCTAssertEqual($0 as? StoryPromptError, .generationFailed)
        }
    }
}

// MARK: - DeviceStoryGenerator

final class DeviceStoryGeneratorTests: XCTestCase {
    func testThrowsModelNotInstalledWhenAbsent() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LiteRTLMModelStore(documentsURL: tmp)
        let generator = DeviceStoryGenerator(modelStore: store)
        do {
            _ = try await generator.generate(from: validSeed())
            XCTFail("expected modelNotInstalled")
        } catch let e as StoryPromptError {
            XCTAssertEqual(e, .modelNotInstalled)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}

// MARK: - LiteRTLMModelStore

final class LiteRTLMModelStoreTests: XCTestCase {
    func testImportModelFromTempFileMakesModelPresent() async throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).litertlm")
        try Data([0x01, 0x02, 0x03, 0x04]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let store = LiteRTLMModelStore(documentsURL: docs)
        let before = await store.isModelPresent()
        XCTAssertFalse(before)
        try await store.importModel(from: source)
        let after = await store.isModelPresent()
        XCTAssertTrue(after)
        let dest = await store.modelFileURL()
        XCTAssertEqual(dest.lastPathComponent, LiteRTLMModelStore.defaultModelFilename)
    }

    func testImportEmptyFileThrows() async throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).litertlm")
        try Data().write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let store = LiteRTLMModelStore(documentsURL: docs)
        do {
            try await store.importModel(from: source)
            XCTFail("expected emptyFile")
        } catch let e as LiteRTLMModelStore.ImportError {
            XCTAssertEqual(e, .emptyFile)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testHostDownloadURLIsKraftekFile() {
        let url = LiteRTLMModelStore.defaultHostDownloadURL.absoluteString
        XCTAssertTrue(url.contains("files.kraftek.dev"))
        XCTAssertTrue(url.contains("gemma-4-E4B-it.litertlm"))
        XCTAssertEqual(LiteRTLMModelStore.defaultModelFilename, "gemma-4-E4B-it.litertlm")
        XCTAssertTrue(
            LiteRTLMModelStore.defaultHostFallbackPageURL.absoluteString.contains("huggingface.co")
        )
    }
}

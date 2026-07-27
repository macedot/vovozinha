import XCTest
import os
@testable import StoryPromptKit
import VovoUI

// MARK: - Test helpers

final class MockMLXBonsaiEngineSession: MLXBonsaiEngineSessioning, @unchecked Sendable {
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

// MARK: - MLXBonsaiStoryGenerator

final class MLXBonsaiStoryGeneratorTests: XCTestCase {
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
        let session = MockMLXBonsaiEngineSession(reply: Self.wellFormedReply)
        let gen = try MLXBonsaiStoryGenerator(
            modelDirectory: URL(fileURLWithPath: "/ignored"),
            session: session
        )
        let draft = try await gen.generate(from: validSeed())
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertEqual(draft.title, "The Glowing Pebble")
    }

    func testPromptIncludesSeedDescription() async throws {
        let session = MockMLXBonsaiEngineSession(reply: Self.wellFormedReply)
        let gen = try MLXBonsaiStoryGenerator(
            modelDirectory: URL(fileURLWithPath: "/ignored"),
            session: session
        )
        let seedText = "a brave little boat sails across a calm silver lake"
        _ = try await gen.generate(from: validSeed(seedText))
        XCTAssertTrue(try XCTUnwrap(session.capturedPrompt).contains(seedText))
    }

    func testNormalizeThrowsWhenTooFew() throws {
        XCTAssertThrowsError(try MLXBonsaiStoryGenerator.normalizeParagraphs("one\n\ntwo")) {
            XCTAssertEqual($0 as? StoryPromptError, .generationFailed)
        }
    }

    func testStripThinkingBlocks() {
        let raw = """
        <think>internal notes</think>
        TITLE: Soft Moon
        SUMMARY: Quiet.

        Para one.

        Para two.

        Para three.

        Para four.

        Para five.

        Para six.

        Para seven.

        Para eight.

        Para nine.

        Para ten.
        """
        let cleaned = MLXBonsaiStoryGenerator.stripThinkingBlocks(raw)
        XCTAssertFalse(cleaned.contains("<think>"))
        let parsed = try? MLXBonsaiStoryGenerator.parse(cleaned)
        XCTAssertEqual(parsed?.paragraphs.count, 10)
    }
}

// MARK: - DeviceStoryGenerator

final class DeviceStoryGeneratorTests: XCTestCase {
    func testThrowsModelNotInstalledWhenAbsent() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BonsaiModelStore(documentsURL: tmp)
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

// MARK: - BonsaiModelStore

final class BonsaiModelStoreTests: XCTestCase {
    func testImportModelFromFolderMakesModelPresent() async throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let pack = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        try Data([0x01, 0x02, 0x03, 0x04]).write(to: pack.appendingPathComponent("model.safetensors"))
        defer { try? FileManager.default.removeItem(at: pack) }

        let store = BonsaiModelStore(documentsURL: docs)
        let before = await store.isModelPresent()
        XCTAssertFalse(before)
        try await store.importModel(from: pack)
        let after = await store.isModelPresent()
        XCTAssertTrue(after)
        let dest = await store.modelDirectory()
        XCTAssertEqual(dest.lastPathComponent, BonsaiModelStore.defaultModelDirectoryName)
    }

    func testImportEmptyFileThrows() async throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try Data().write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let store = BonsaiModelStore(documentsURL: docs)
        do {
            try await store.importModel(from: source)
            XCTFail("expected emptyFile")
        } catch let e as BonsaiModelStore.ImportError {
            XCTAssertEqual(e, .emptyFile)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testHostDownloadURLIsKraftekZip() {
        let url = BonsaiModelStore.defaultHostDownloadURL.absoluteString
        XCTAssertTrue(url.contains("files.kraftek.dev"))
        XCTAssertTrue(url.contains("Bonsai-27B-mlx-1bit.zip"))
        XCTAssertEqual(BonsaiModelStore.defaultModelDirectoryName, "Bonsai-27B-mlx-1bit")
        XCTAssertTrue(
            BonsaiModelStore.defaultHostFallbackPageURL.absoluteString
                .contains("prism-ml/Bonsai-27B-mlx-1bit")
        )
    }

    func testDirectoryLooksLikeMLXPack() throws {
        let pack = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pack) }

        XCTAssertFalse(BonsaiModelStore.directoryLooksLikeMLXPack(pack))
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        XCTAssertFalse(BonsaiModelStore.directoryLooksLikeMLXPack(pack))
        try Data([0x01]).write(to: pack.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(BonsaiModelStore.directoryLooksLikeMLXPack(pack))
    }
}

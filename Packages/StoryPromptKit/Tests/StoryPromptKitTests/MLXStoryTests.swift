import XCTest
import os
@testable import StoryPromptKit
import VovoUI

// MARK: - Test helpers

final class MockMLXStoryEngineSession: MLXStoryEngineSessioning, @unchecked Sendable {
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

// MARK: - MLXStoryGenerator

final class MLXStoryGeneratorTests: XCTestCase {
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
        let session = MockMLXStoryEngineSession(reply: Self.wellFormedReply)
        let gen = try MLXStoryGenerator(
            modelDirectory: URL(fileURLWithPath: "/ignored"),
            session: session
        )
        let draft = try await gen.generate(from: validSeed())
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertEqual(draft.title, "The Glowing Pebble")
    }

    func testPromptIncludesSeedDescription() async throws {
        let session = MockMLXStoryEngineSession(reply: Self.wellFormedReply)
        let gen = try MLXStoryGenerator(
            modelDirectory: URL(fileURLWithPath: "/ignored"),
            session: session
        )
        let seedText = "a brave little boat sails across a calm silver lake"
        _ = try await gen.generate(from: validSeed(seedText))
        XCTAssertTrue(try XCTUnwrap(session.capturedPrompt).contains(seedText))
    }

    func testNormalizeThrowsWhenTooFew() throws {
        XCTAssertThrowsError(try MLXStoryGenerator.normalizeParagraphs("one\n\ntwo")) {
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
        let cleaned = MLXStoryGenerator.stripThinkingBlocks(raw)
        XCTAssertFalse(cleaned.contains("<think>"))
        let parsed = try? MLXStoryGenerator.parse(cleaned)
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

        let store = OnDeviceMLXModelStore(documentsURL: tmp)
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

// MARK: - OnDeviceMLXModelStore

final class OnDeviceMLXModelStoreTests: XCTestCase {
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

        let store = OnDeviceMLXModelStore(documentsURL: docs)
        let before = await store.isModelPresent()
        XCTAssertFalse(before)
        try await store.importModel(from: pack)
        let after = await store.isModelPresent()
        XCTAssertTrue(after)
        let dest = await store.modelDirectory()
        XCTAssertEqual(dest.lastPathComponent, OnDeviceMLXModelStore.defaultModelDirectoryName)
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

        let store = OnDeviceMLXModelStore(documentsURL: docs)
        do {
            try await store.importModel(from: source)
            XCTFail("expected emptyFile")
        } catch let e as OnDeviceMLXModelStore.ImportError {
            XCTAssertEqual(e, .emptyFile)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testDefaultModelPathIsUnderApplicationSupportNotDocuments() async {
        let store = OnDeviceMLXModelStore()
        let dir = await store.modelDirectory()
        let path = dir.path
        XCTAssertTrue(
            path.contains("Application Support") || path.contains("Application%20Support")
                || path.contains("Library"),
            "expected Application Support-style path, got \(path)"
        )
        XCTAssertFalse(path.contains("/Documents/Vovozinha/Models"), path)
        XCTAssertEqual(dir.lastPathComponent, OnDeviceMLXModelStore.defaultModelDirectoryName)
    }

    func testHostDownloadURLIsKraftekZip() {
        let url = OnDeviceMLXModelStore.defaultHostDownloadURL.absoluteString
        XCTAssertTrue(url.contains("vovo.kraftek.cloud"))
        XCTAssertFalse(url.contains("files.kraftek.dev"))
        XCTAssertFalse(url.contains("huggingface.co"))
        XCTAssertTrue(url.contains("Qwen3.5-4B-MLX-4bit.zip"))
        XCTAssertEqual(OnDeviceMLXModelStore.defaultModelDirectoryName, "Qwen3.5-4B-MLX-4bit")
        XCTAssertTrue(
            OnDeviceMLXModelStore.defaultHostSHA256URL.absoluteString.hasSuffix(".zip.sha256")
        )
        XCTAssertTrue(
            OnDeviceMLXModelStore.defaultHostSHA256URL.absoluteString.contains("vovo.kraftek.cloud")
        )
    }

    func testParseSHA256FileAcceptsShasumAndBareHex() throws {
        let hex = String(repeating: "ab", count: 32) // 64 chars
        XCTAssertEqual(
            try OnDeviceMLXModelStore.parseSHA256File("\(hex)  Qwen3.5-4B-MLX-4bit.zip\n"),
            hex
        )
        XCTAssertEqual(try OnDeviceMLXModelStore.parseSHA256File("\(hex)\n"), hex)
        XCTAssertEqual(
            try OnDeviceMLXModelStore.parseSHA256File("# comment\n\(hex.uppercased())  file.zip\n"),
            hex
        )
        XCTAssertThrowsError(try OnDeviceMLXModelStore.parseSHA256File("not-a-hash")) {
            XCTAssertEqual($0 as? OnDeviceMLXModelStore.DownloadError, .checksumFileInvalid)
        }
    }

    func testDownloadProgressFormatsDurationAndETA() {
        let snap = ModelDownloadProgress(
            fraction: 0.5,
            bytesReceived: 500_000_000,
            bytesTotal: 1_000_000_000,
            bytesPerSecond: 10_000_000,
            elapsed: 50,
            estimatedRemaining: 50,
            phase: .downloading
        )
        XCTAssertEqual(ModelDownloadProgress.formatDuration(65), "1:05")
        XCTAssertEqual(ModelDownloadProgress.formatDuration(3661), "1:01:01")
        XCTAssertEqual(snap.formattedElapsed, "0:50")
        XCTAssertEqual(snap.formattedETA, "0:50")
        XCTAssertFalse(snap.formattedSpeed.isEmpty)
        XCTAssertNotNil(snap.formattedTotal)
    }

    func testVerifySHA256AcceptsMatchingFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let payload = Data("vovozinha-host-pack".utf8)
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hex = try OnDeviceMLXModelStore.sha256Hex(ofFileAt: tmp)
        XCTAssertNoThrow(try OnDeviceMLXModelStore.verifySHA256(ofFileAt: tmp, expectedHex: hex))
        XCTAssertThrowsError(
            try OnDeviceMLXModelStore.verifySHA256(ofFileAt: tmp, expectedHex: String(repeating: "0", count: 64))
        ) {
            XCTAssertEqual($0 as? OnDeviceMLXModelStore.DownloadError, .checksumMismatch)
        }
    }

    func testDirectoryLooksLikeMLXPack() throws {
        let pack = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pack) }

        XCTAssertFalse(OnDeviceMLXModelStore.directoryLooksLikeMLXPack(pack))
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        XCTAssertFalse(OnDeviceMLXModelStore.directoryLooksLikeMLXPack(pack))
        try Data([0x01]).write(to: pack.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(OnDeviceMLXModelStore.directoryLooksLikeMLXPack(pack))
    }

    func testRecordedInstallSHA256AndRemoveClearsSidecar() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = OnDeviceMLXModelStore(storageRootURL: root, sha256URL: nil)
        let pack = await store.modelDirectory()
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        try Data([0x01]).write(to: pack.appendingPathComponent("model.safetensors"))

        let hex = String(repeating: "ab", count: 32)
        let sidecar = await store.installedSHA256SidecarURL()
        try Data(hex.utf8).write(to: sidecar)

        let recorded = await store.recordedInstallSHA256()
        XCTAssertEqual(recorded, hex)
        let presentBefore = await store.isModelPresent()
        XCTAssertTrue(presentBefore)

        try await store.removeModel()
        let presentAfter = await store.isModelPresent()
        let recordedAfter = await store.recordedInstallSHA256()
        XCTAssertFalse(presentAfter)
        XCTAssertNil(recordedAfter)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testImportClearsRecordedInstallSHA256() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = OnDeviceMLXModelStore(storageRootURL: root, sha256URL: nil)
        let pack = await store.modelDirectory()
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        try Data([0x01]).write(to: pack.appendingPathComponent("model.safetensors"))

        let hex = String(repeating: "cd", count: 32)
        try Data(hex.utf8).write(to: await store.installedSHA256SidecarURL())
        let recordedBefore = await store.recordedInstallSHA256()
        XCTAssertEqual(recordedBefore, hex)

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("{}".utf8).write(to: source.appendingPathComponent("config.json"))
        try Data([0x02]).write(to: source.appendingPathComponent("model.safetensors"))

        try await store.importModel(from: source)
        let present = await store.isModelPresent()
        let recordedAfter = await store.recordedInstallSHA256()
        XCTAssertTrue(present)
        XCTAssertNil(recordedAfter)
    }

    func testCheckForHostUpdateComparesRemoteSidecar() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let localHex = String(repeating: "11", count: 32)
        let remoteHex = String(repeating: "22", count: 32)
        let remoteFile = root.appendingPathComponent("remote.sha256")
        try Data("\(remoteHex)  Qwen3.5-4B-MLX-4bit.zip\n".utf8).write(to: remoteFile)

        let store = OnDeviceMLXModelStore(
            storageRootURL: root,
            sha256URL: remoteFile
        )
        let pack = await store.modelDirectory()
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        try Data([0x01]).write(to: pack.appendingPathComponent("model.safetensors"))
        try Data(localHex.utf8).write(to: await store.installedSHA256SidecarURL())

        let needsUpdate = await store.checkForHostUpdate()
        XCTAssertTrue(needsUpdate)

        try Data(remoteHex.utf8).write(to: await store.installedSHA256SidecarURL())
        let upToDate = await store.checkForHostUpdate()
        XCTAssertFalse(upToDate)
    }

    func testCheckForHostUpdateFalseWithoutRecordedHash() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let remoteHex = String(repeating: "33", count: 32)
        let remoteFile = root.appendingPathComponent("remote.sha256")
        try Data("\(remoteHex)\n".utf8).write(to: remoteFile)

        let store = OnDeviceMLXModelStore(storageRootURL: root, sha256URL: remoteFile)
        let pack = await store.modelDirectory()
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.appendingPathComponent("config.json"))
        try Data([0x01]).write(to: pack.appendingPathComponent("model.safetensors"))

        let recorded = await store.recordedInstallSHA256()
        let needsUpdate = await store.checkForHostUpdate()
        XCTAssertNil(recorded)
        XCTAssertFalse(needsUpdate)
    }
}

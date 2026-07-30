import CoreImage
import XCTest
import VovoUI
@testable import PhotoDescribeKit
import StoryPromptKit

final class PhotoDescribeKitTests: XCTestCase {
    func testDescribePromptLoadsForLanguages() {
        for lang in [AppLanguage.englishUS, .portugueseBrazil, .spanishSpain] {
            let prompt = PhotoDescribeTemplate.filledDescribePrompt(language: lang)
            XCTAssertFalse(prompt.isEmpty, "empty prompt for \(lang)")
            XCTAssertTrue(
                prompt.lowercased().contains("person")
                    || prompt.lowercased().contains("pesso")
                    || prompt.lowercased().contains("persona"),
                "expected persons priority in \(lang): \(prompt.prefix(80))"
            )
        }
    }

    func testNormalizeCaptionCollapsesNewlines() {
        let raw = "A child in a red coat.\n\nA wooden toy on the floor.\n"
        let cleaned = MLXPhotoDescriber.normalizeCaption(raw)
        XCTAssertEqual(cleaned, "A child in a red coat. A wooden toy on the floor.")
    }

    func testStripThinkingBlocks() {
        let raw = "<think>plan</think>\nA sunny park with two kids."
        XCTAssertEqual(
            MLXPhotoDescriber.normalizeCaption(MLXPhotoDescriber.stripThinkingBlocks(raw)),
            "A sunny park with two kids."
        )
    }

    func testEmptyImageIsInvalid() {
        let input = PhotoDescribeInput(imageData: Data())
        XCTAssertTrue(input.isEmpty)
        XCTAssertNil(input.makeCIImage())
    }

    func testDeviceDescriberThrowsWhenModelMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = OnDeviceMLXModelStore(storageRootURL: root, sha256URL: nil)
        let describer = DevicePhotoDescriber(modelStore: store) { _ in
            MockPhotoSession(reply: "should not run")
        }

        // 1x1 PNG
        let png = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        do {
            _ = try await describer.describe(
                PhotoDescribeInput(imageData: png),
                language: .englishUS
            )
            XCTFail("expected modelNotInstalled")
        } catch let e as PhotoDescribeError {
            XCTAssertEqual(e, .modelNotInstalled)
        }
    }

    func testMLXPhotoDescriberUsesSession() async throws {
        let session = MockPhotoSession(reply: "A child holds a blue ball in a sunny garden.")
        let describer = MLXPhotoDescriber(session: session)
        let png = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let caption = try await describer.describe(
            PhotoDescribeInput(imageData: png),
            language: .englishUS
        )
        XCTAssertEqual(caption.text, "A child holds a blue ball in a sunny garden.")
        XCTAssertEqual(caption.language, .englishUS)
        XCTAssertEqual(session.callCount, 1)
    }

    func testMLXPhotoDescriberEmptyReplyFails() async throws {
        let describer = MLXPhotoDescriber(session: MockPhotoSession(reply: "   "))
        let png = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        do {
            _ = try await describer.describe(
                PhotoDescribeInput(imageData: png),
                language: .englishUS
            )
            XCTFail("expected describeFailed")
        } catch let e as PhotoDescribeError {
            XCTAssertEqual(e, .describeFailed)
        }
    }
}

private final class MockPhotoSession: MLXPhotoDescribeSessioning, @unchecked Sendable {
    let reply: String
    private(set) var callCount = 0

    init(reply: String) {
        self.reply = reply
    }

    func send(prompt: String, image: CIImage) async throws -> String {
        callCount += 1
        _ = prompt
        _ = image
        return reply
    }
}

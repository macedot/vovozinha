import CoreGraphics
import XCTest
import ImageGenKit
import PhotoDescribeKit
import StoryPromptKit
import VovoUI
@testable import StorybookKit

final class StorybookKitTests: XCTestCase {

    func testBaseSeedIsStableAndNotHashValue() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let a = StoryIdentity.baseSeed(storyID: id)
        let b = StoryIdentity.baseSeed(storyID: id)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, 0)
        XCTAssertEqual(
            StoryIdentity.pageSeed(storyID: id, pageIndex: 3),
            a &+ 3
        )
    }

    func testParserRequiresTenLinesAndCharacter() throws {
        var body = "CHARACTER: little girl, red coat, brown hair\n"
        for i in 1...10 { body += "\(i). scene \(i) in the garden\n" }
        let plan = try IllustrationPromptParser.parse(body)
        XCTAssertEqual(plan.characterDescriptor, "little girl, red coat, brown hair")
        XCTAssertEqual(plan.prompts.count, 10)
        XCTAssertEqual(plan.prompts[0], "scene 1 in the garden")
    }

    func testParserNeverFabricatesMissingLine() {
        var body = "CHARACTER: teddy bear, blue scarf\n"
        for i in 1...9 { body += "\(i). scene \(i)\n" }
        XCTAssertThrowsError(try IllustrationPromptParser.parse(body)) { error in
            XCTAssertEqual(error as? IllustrationPromptError, .missingLines([10]))
        }
    }

    func testParserRejectsMissingCharacter() {
        var body = ""
        for i in 1...10 { body += "\(i). scene \(i)\n" }
        XCTAssertThrowsError(try IllustrationPromptParser.parse(body)) { error in
            XCTAssertEqual(error as? IllustrationPromptError, .missingCharacterDescriptor)
        }
    }

    func testParserAcceptsMarkdownFencesAndBold() throws {
        var body = "```\n**CHARACTER:** little girl, red coat\n"
        for i in 1...10 { body += "**\(i).** scene \(i) in the garden\n" }
        body += "```\n"
        let plan = try IllustrationPromptParser.parse(body)
        XCTAssertEqual(plan.characterDescriptor, "little girl, red coat")
        XCTAssertEqual(plan.prompts.count, 10)
        XCTAssertEqual(plan.prompts[0], "scene 1 in the garden")
    }

    func testClipPromptPutsSceneFirst() {
        let pipeline = makePipeline()
        let prompt = pipeline.clipPrompt(
            scene: "the hero opens a glowing door in the woods",
            lock: "little girl red coat brown hair"
        )
        XCTAssertTrue(prompt.hasPrefix("the hero opens a glowing door in the woods"))
        XCTAssertTrue(prompt.contains("little girl"))
    }

    func testKidsNegativeLockIsOnEveryRender() {
        let negative = ImageGenTemplate.defaultNegativePrompt.lowercased()
        for term in ["photorealistic", "nsfw", "violence", "text", "adult", "weapon"] {
            XCTAssertTrue(negative.contains(term), "missing \(term)")
        }
        let pipeline = makePipeline()
        XCTAssertTrue(pipeline.negativePrompt.lowercased().contains("nsfw"))
    }

    func testPipelineEmitsTextsThenPagesInCoverFirstOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = makePipeline(storeRoot: root)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let storyID = UUID()
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: seed, photo: nil, storyID: storyID) {
            events.append(event)
        }

        XCTAssertTrue(events.contains(where: {
            if case .pageTextsReady(let pages, _, _) = $0 { return pages.count == 10 }
            return false
        }))
        let ready = events.compactMap { event -> Int? in
            if case .illustrationReady(let index, _) = event { return index }
            return nil
        }
        XCTAssertEqual(ready, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(events.last, .finished)

        let store = StoryFileStore(rootURL: root)
        XCTAssertFalse(store.pngExists(id: storyID, fileName: StoryFileStore.referenceFileName))
        XCTAssertTrue(store.pngExists(id: storyID, fileName: store.pageFileName(index: 1)))
        XCTAssertTrue(store.pngExists(id: storyID, fileName: store.pageFileName(index: 10)))
    }

    func testPagesAreTextToImageAndPhotoBytesAreNotSent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = try XCTUnwrap(Self.makeCGImage())
        let images = CountingImageGenerator(image: image)
        let pipeline = SeedPipeline(
            storyGenerator: MockStoryGenerator(),
            illustrationPrompts: MockIllustrationPrompts(),
            imageGenerator: images,
            photoDescriber: MockPhotoDescriber(),
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: root)
        )
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let photo = PhotoDescribeInput(imageData: Data(repeating: 7, count: 64))
        for await _ in pipeline.run(seed: seed, photo: photo, storyID: UUID()) {}
        XCTAssertEqual(images.calls, 10)
        XCTAssertEqual(images.modes, Array(repeating: ImageGenMode.textToImage, count: 10))
        XCTAssertFalse(images.receivedNonEmptyImage)
    }

    func testResumeSkipsExistingPageFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storyID = UUID()
        let store = StoryFileStore(rootURL: root)
        let image = try XCTUnwrap(Self.makeCGImage())
        _ = try store.writePNG(image, id: storyID, fileName: store.pageFileName(index: 1))

        let images = CountingImageGenerator(image: image)
        let pipeline = makePipeline(storeRoot: root, images: images)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        for await _ in pipeline.run(seed: seed, photo: nil, storyID: storyID) {}

        // Page 1 already on disk → 9 remaining txt2img page renders.
        XCTAssertEqual(images.calls, 9)
        XCTAssertTrue(images.modes.allSatisfy { $0 == .textToImage })
    }

    func testStoryTextsAreEmittedEvenIfIllustrationPromptsFail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = try XCTUnwrap(Self.makeCGImage())
        let images = CountingImageGenerator(image: image)
        let pipeline = SeedPipeline(
            storyGenerator: MockStoryGenerator(),
            illustrationPrompts: FailingIllustrationPrompts(),
            imageGenerator: images,
            photoDescriber: nil,
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: root)
        )
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: seed, photo: nil, storyID: UUID()) {
            events.append(event)
        }

        XCTAssertTrue(events.contains(where: {
            if case .pageTextsReady(let pages, let title, _) = $0 {
                return pages.count == 10 && title == "Lantern Garden"
            }
            return false
        }))
        let ready = events.compactMap { event -> Int? in
            if case .illustrationReady(let index, _) = event { return index }
            return nil
        }
        XCTAssertEqual(ready, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(images.calls, 10)
        XCTAssertFalse(events.contains(where: {
            if case .failed = $0 { return true }
            return false
        }))
        XCTAssertEqual(events.last, .finished)
    }

    func testPageTextsReadyComesBeforeIllustrationPromptPhase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = makePipeline(storeRoot: root)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: seed, photo: nil, storyID: UUID()) {
            events.append(event)
        }
        let textIndex = events.firstIndex { event in
            if case .pageTextsReady = event { return true }
            return false
        }
        let promptPhaseIndex = events.firstIndex { event in
            if case .phaseChanged(.illustrationPrompts) = event { return true }
            return false
        }
        let texts = try XCTUnwrap(textIndex)
        let prompts = try XCTUnwrap(promptPhaseIndex)
        XCTAssertLessThan(texts, prompts)
    }

    func testImageFailureDoesNotDropTheStory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = SeedPipeline(
            storyGenerator: MockStoryGenerator(),
            illustrationPrompts: MockIllustrationPrompts(),
            imageGenerator: ThrowingImageGenerator(),
            photoDescriber: nil,
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: root)
        )
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: seed, photo: nil, storyID: UUID()) {
            events.append(event)
        }
        XCTAssertTrue(events.contains(where: {
            if case .pageTextsReady(let pages, _, _) = $0 { return pages.count == 10 }
            return false
        }))
        XCTAssertFalse(events.contains(where: {
            if case .illustrationReady = $0 { return true }
            return false
        }))
        XCTAssertEqual(events.last, .finished)
    }

    func testCancelStopsBeforeImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = makePipeline(storeRoot: root)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let stream = pipeline.run(seed: seed, photo: nil)
        let iteratorTask = Task {
            var n = 0
            for await _ in stream {
                n += 1
                if n >= 2 { break }
            }
        }
        iteratorTask.cancel()
        _ = await iteratorTask.result
    }

    private func makePipeline(
        storeRoot: URL = FileManager.default.temporaryDirectory,
        images: CountingImageGenerator? = nil
    ) -> SeedPipeline {
        let image = images ?? CountingImageGenerator(image: Self.makeCGImage()!)
        return SeedPipeline(
            storyGenerator: MockStoryGenerator(),
            illustrationPrompts: MockIllustrationPrompts(),
            imageGenerator: image,
            photoDescriber: nil,
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: storeRoot)
        )
    }

    private static func makeCGImage() -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()
    }
}

private struct MockStoryGenerator: StoryFromPromptGenerating {
    func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()
        return StoryDraft(
            title: "Lantern Garden",
            summary: "A kitten finds a lantern.",
            seedPrompt: prompt.trimmed,
            paragraphs: (1...10).map { "Paragraph \($0) of the bedtime story." },
            language: prompt.language
        )
    }
}

private struct MockIllustrationPrompts: IllustrationPromptGenerating {
    func generate(draftTitle: String, paragraphs: [String], caption: String?) async throws -> IllustrationPlan {
        IllustrationPlan(
            characterDescriptor: "orange kitten, round eyes",
            prompts: (1...10).map { "page \($0) garden lantern scene" }
        )
    }
}

private struct FailingIllustrationPrompts: IllustrationPromptGenerating {
    func generate(draftTitle: String, paragraphs: [String], caption: String?) async throws -> IllustrationPlan {
        throw IllustrationPromptError.missingCharacterDescriptor
    }
}

private struct NoopMemory: MemorySequencing {
    func releaseMLX() async {}
    func prepareCoreML() async throws {}
    func releaseCoreML() async {}
}

private struct MockPhotoDescriber: PhotoDescribing {
    func describe(_ image: PhotoDescribeInput, language: AppLanguage) async throws -> PhotoCaption {
        PhotoCaption(text: "child, brown hair, red coat, blue bicycle", language: language)
    }
}

private struct ThrowingImageGenerator: ImageGenerating {
    func generate(_ input: ImageGenInput, config: ImageGenConfig) async throws -> ImageGenResult {
        throw ImageGenError.generationFailed
    }
}

final class CountingImageGenerator: ImageGenerating, @unchecked Sendable {
    let image: CGImage
    private(set) var calls = 0
    private(set) var modes: [ImageGenMode] = []
    private(set) var receivedNonEmptyImage = false
    init(image: CGImage) { self.image = image }
    func generate(_ input: ImageGenInput, config: ImageGenConfig) async throws -> ImageGenResult {
        calls += 1
        modes.append(config.mode)
        if !input.isEmpty { receivedNonEmptyImage = true }
        return ImageGenResult(cgImage: image, seed: config.seed ?? 0, elapsedSeconds: 0, bucket: .square)
    }
}

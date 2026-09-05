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

    func testClipPromptBudgetKeepsLockAndStyleIntact() {
        let pipeline = makePipeline()
        let hugeScene = Array(repeating: "meadow", count: 60).joined(separator: " ")
        let hugeLock = Array(repeating: "trait", count: 40).joined(separator: " ")
        let a = pipeline.clipPrompt(scene: hugeScene, lock: hugeLock)
        let b = pipeline.clipPrompt(scene: "short scene", lock: hugeLock)

        // Nothing past token 75 is dropped: the whole prompt fits the budget.
        XCTAssertLessThanOrEqual(
            SeedPipeline.wordCount([a]),
            SeedPipeline.totalWordBudget
        )
        XCTAssertLessThanOrEqual(
            SeedPipeline.wordCount([b]),
            SeedPipeline.totalWordBudget
        )

        // The identity lock and the style core are byte-identical across pages —
        // variable scene length can no longer move the truncation point.
        let styleCore = SeedPipeline.words(in: pipeline.stylePrefix, limit: SeedPipeline.styleWordLimit)
        let lockBit = SeedPipeline.words(in: hugeLock, limit: SeedPipeline.lockWordLimit)
        for prompt in [a, b] {
            XCTAssertTrue(prompt.hasSuffix(styleCore))
            XCTAssertTrue(prompt.contains(", \(lockBit), \(styleCore)"))
        }
        XCTAssertEqual(
            a.suffix(from: a.index(a.endIndex, offsetBy: -styleCore.count)),
            b.suffix(from: b.index(b.endIndex, offsetBy: -styleCore.count))
        )
    }

    func testRepairRetryMergesMissingLinesOnly() async throws {
        var body = "CHARACTER: little girl, red coat, brown hair\n"
        for i in 1...6 { body += "\(i). scene \(i) in the garden\n" }
        var repair = ""
        for i in 7...10 { repair += "\(i). scene \(i) under the moon\n" }

        let completer = ScriptedCompleter(replies: [body, repair])
        let generator = DeviceIllustrationPromptGenerator(completer: completer)
        let plan = try await generator.generate(
            draftTitle: "Lantern Garden",
            paragraphs: (1...10).map { "Paragraph \($0)." },
            elementsBlock: ""
        )

        XCTAssertEqual(plan.characterDescriptor, "little girl, red coat, brown hair")
        XCTAssertEqual(plan.prompts.count, 10)
        XCTAssertEqual(plan.prompts[6], "scene 7 under the moon")
        XCTAssertEqual(completer.prompts.count, 2)
        // The repair pass asks only for what is missing.
        XCTAssertTrue(completer.prompts[1].contains("7, 8, 9, 10"))
        XCTAssertFalse(completer.prompts[1].contains("lines 1"))
    }

    func testRepairStillIncompleteThrowsInsteadOfFabricating() async throws {
        var body = "CHARACTER: little girl, red coat, brown hair\n"
        for i in 1...4 { body += "\(i). scene \(i)\n" }
        var repair = ""
        for i in 5...8 { repair += "\(i). scene \(i)\n" }

        let completer = ScriptedCompleter(replies: [body, repair])
        let generator = DeviceIllustrationPromptGenerator(completer: completer)
        do {
            _ = try await generator.generate(
                draftTitle: "Lantern Garden",
                paragraphs: (1...10).map { "Paragraph \($0)." },
                elementsBlock: ""
            )
            XCTFail("expected missingLines([9, 10])")
        } catch let error as IllustrationPromptError {
            XCTAssertEqual(error, .missingLines([9, 10]))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
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
        XCTAssertTrue(store.pngExists(id: storyID, fileName: StoryFileStore.referenceFileName))
        XCTAssertTrue(store.pngExists(id: storyID, fileName: store.pageFileName(index: 1)))
        XCTAssertTrue(store.pngExists(id: storyID, fileName: store.pageFileName(index: 10)))
    }

    func testPhotoFeedsReferenceThenPagesChainFromEachOther() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = try XCTUnwrap(Self.makeCGImage())
        // Varied output: every render writes a distinct PNG, so "page N's input ==
        // page N-1's PNG" is a real assertion, not an artifact of equal bytes.
        let images = CountingImageGenerator(image: image, varied: true)
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
        let photoBytes = Data(repeating: 7, count: 64)
        let photo = PhotoDescribeInput(imageData: photoBytes)
        let storyID = UUID()
        for await _ in pipeline.run(seed: seed, photo: photo, storyID: storyID) {}

        // 1 photo→reference img2img + 10 chained page img2img renders.
        XCTAssertEqual(images.calls, 11)
        XCTAssertEqual(images.modes.first, .imageToImage)
        XCTAssertTrue(images.modes.dropFirst().allSatisfy { $0 == .imageToImage })
        // The photo bytes reach the generator exactly once — the reference pass.
        XCTAssertEqual(images.inputs.filter { $0 == photoBytes }.count, 1)

        let store = StoryFileStore(rootURL: root)
        let directory = store.storyDirectory(id: storyID)
        let referenceData = try Data(
            contentsOf: directory.appendingPathComponent(StoryFileStore.referenceFileName)
        )
        // Page 1 chains from the stored reference PNG…
        XCTAssertEqual(images.inputs[1], referenceData)
        // …and every next page chains from the PREVIOUS page's PNG, never the
        // raw photo and never the reference again.
        for pageIndex in 2...10 {
            let previous = try Data(
                contentsOf: directory.appendingPathComponent(store.pageFileName(index: pageIndex - 1))
            )
            XCTAssertEqual(images.inputs[pageIndex], previous, "page \(pageIndex) chain base")
        }
        XCTAssertNotEqual(referenceData, photoBytes)
        // Reference pass runs hot; chained page passes stay at the chain strength.
        XCTAssertEqual(images.strengths.first, SeedPipeline.referenceStrength)
        XCTAssertTrue(images.strengths.dropFirst().allSatisfy { $0 == SeedPipeline.chainStrength })
    }

    func testNoPhotoTxt2imgReferenceThenChainedPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = try XCTUnwrap(Self.makeCGImage())
        let images = CountingImageGenerator(image: image, varied: true)
        let pipeline = makePipeline(storeRoot: root, images: images)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let storyID = UUID()
        for await _ in pipeline.run(seed: seed, photo: nil, storyID: storyID) {}

        // 1 txt2img character sheet + 10 chained pages.
        XCTAssertEqual(images.calls, 11)
        XCTAssertEqual(images.modes.first, .textToImage)
        XCTAssertTrue(images.modes.dropFirst().allSatisfy { $0 == .imageToImage })
        XCTAssertEqual(images.inputs.first?.isEmpty, true)
        let store = StoryFileStore(rootURL: root)
        let directory = store.storyDirectory(id: storyID)
        let referenceData = try Data(
            contentsOf: directory.appendingPathComponent(StoryFileStore.referenceFileName)
        )
        XCTAssertEqual(images.inputs[1], referenceData)
        for pageIndex in 2...10 {
            let previous = try Data(
                contentsOf: directory.appendingPathComponent(store.pageFileName(index: pageIndex - 1))
            )
            XCTAssertEqual(images.inputs[pageIndex], previous, "page \(pageIndex) chain base")
        }
    }

    func testResumeSkipsExistingPageFilesAndChainsFromLastGoodPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storyID = UUID()
        let store = StoryFileStore(rootURL: root)
        // Reference (orange) and page 1 (blue) differ, so chaining from page 1 —
        // not from the reference — is observable.
        let referenceImage = try XCTUnwrap(Self.makeCGImage())
        let pageOneImage = try XCTUnwrap(Self.solidImage(red: 0.2, green: 0.4, blue: 0.9))
        _ = try store.writePNG(referenceImage, id: storyID, fileName: StoryFileStore.referenceFileName)
        _ = try store.writePNG(pageOneImage, id: storyID, fileName: store.pageFileName(index: 1))
        let pageOneData = try Data(
            contentsOf: store.storyDirectory(id: storyID)
                .appendingPathComponent(store.pageFileName(index: 1))
        )

        let images = CountingImageGenerator(image: referenceImage, varied: true)
        let pipeline = makePipeline(storeRoot: root, images: images)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        for await _ in pipeline.run(seed: seed, photo: nil, storyID: storyID) {}

        // Reference and page 1 already on disk → 9 remaining page renders, all
        // img2img, and page 2 chains from the existing page-1 PNG.
        XCTAssertEqual(images.calls, 9)
        XCTAssertTrue(images.modes.allSatisfy { $0 == .imageToImage })
        XCTAssertEqual(images.inputs.first, pageOneData)
    }

    func testFailedPageChainsFromLastGoodPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storyID = UUID()
        let pageTwoSeed = StoryIdentity.pageSeed(storyID: storyID, pageIndex: 2)
        let image = try XCTUnwrap(Self.makeCGImage())
        let images = CountingImageGenerator(image: image, varied: true, failSeeds: [pageTwoSeed])
        let pipeline = makePipeline(storeRoot: root, images: images)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        for await _ in pipeline.run(seed: seed, photo: nil, storyID: storyID) {}

        let store = StoryFileStore(rootURL: root)
        let directory = store.storyDirectory(id: storyID)
        // Page 2 failed; every other page exists.
        XCTAssertFalse(store.pngExists(id: storyID, fileName: store.pageFileName(index: 2)))
        for index in [1] + Array(3...10) {
            XCTAssertTrue(store.pngExists(id: storyID, fileName: store.pageFileName(index: index)))
        }
        XCTAssertEqual(images.calls, 11) // reference + 10 attempts (page 2 threw)

        // Page 3 chained from page 1 — the newest GOOD page — not from the
        // reference and not from the failed page.
        let pageOneData = try Data(
            contentsOf: directory.appendingPathComponent(store.pageFileName(index: 1))
        )
        XCTAssertEqual(images.inputs[2], pageOneData) // page 2 attempt
        XCTAssertEqual(images.inputs[3], pageOneData) // page 3 chain base
    }

    func testPhaseOrderIncludesBibleBetweenCaptionAndStory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = makePipeline(storeRoot: root)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        var phases: [PipelinePhase] = []
        for await event in pipeline.run(seed: seed, photo: nil, storyID: UUID()) {
            if case .phaseChanged(let phase) = event { phases.append(phase) }
        }
        XCTAssertEqual(
            phases,
            [.caption, .bible, .story, .illustrationPrompts, .reference, .pages, .finished]
        )
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
        XCTAssertEqual(images.calls, 11)
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

    func testStorybookJSONRoundTripAndDelete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StoryFileStore(rootURL: root)
        let book = Storybook(
            id: UUID(),
            title: "Lantern Garden",
            summary: "A kitten finds a lantern.",
            language: "en-US",
            seedPrompt: "a brave kitten finds a lantern",
            characterDescriptor: "orange kitten, round eyes",
            baseSeed: 7,
            phase: .pages,
            pages: [
                StoryPage(index: 1, text: "p1", illustrationPrompt: "sc1", imageFileName: "page-1.png"),
                StoryPage(index: 2, text: "p2", illustrationPrompt: "sc2"),
            ],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try store.saveStorybook(book)

        let loaded = try XCTUnwrap(store.loadStorybook(id: book.id))
        XCTAssertEqual(loaded, book)
        XCTAssertEqual(store.loadAllStorybooks(), [book])

        try store.deleteStory(id: book.id)
        XCTAssertNil(store.loadStorybook(id: book.id))
        XCTAssertTrue(store.loadAllStorybooks().isEmpty)
    }

    func testLoadAllSkipsDirectoriesWithoutStoryJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StoryFileStore(rootURL: root)
        let book = Storybook(
            id: UUID(), title: "T", summary: "S", language: "pt-BR", seedPrompt: "seed",
            characterDescriptor: "", baseSeed: 1, phase: .story,
            pages: (1...10).map { StoryPage(index: $0, text: "p\($0)", illustrationPrompt: "sc") }
        )
        try store.saveStorybook(book)
        _ = try store.ensureStoryDirectory(id: UUID()) // interrupted run: PNGs only, no story.json

        XCTAssertEqual(store.loadAllStorybooks().map(\.id), [book.id])
    }

    func testPipelinePersistsStorybookAtMilestones() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = makePipeline(storeRoot: root)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let storyID = UUID()
        for await _ in pipeline.run(seed: seed, photo: nil, storyID: storyID) {}

        let store = StoryFileStore(rootURL: root)
        let saved = try XCTUnwrap(store.loadStorybook(id: storyID))
        XCTAssertEqual(saved.phase, .finished)
        XCTAssertEqual(saved.title, "Lantern Garden")
        XCTAssertEqual(saved.language, "en-US")
        XCTAssertEqual(saved.seedPrompt, seed.trimmed)
        XCTAssertEqual(saved.baseSeed, StoryIdentity.baseSeed(storyID: storyID))
        XCTAssertEqual(saved.characterDescriptor, "orange kitten, round eyes")
        XCTAssertEqual(saved.pages.count, 10)
        XCTAssertTrue(saved.pages.allSatisfy { $0.imageFileName != nil })
    }

    func testBibleFeedsStoryAndIllustrationPassesAndIsPersisted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bible = StoryBible(
            characterLock: "little girl, dark braids, red coat",
            supporting: "",
            setting: "cozy garden",
            props: ["red rose"]
        )
        let bibleGenerator = RecordingBibleGenerator(bible: bible)
        let storyGenerator = MockStoryGenerator()
        let illustrationPrompts = MockIllustrationPrompts()
        let image = try XCTUnwrap(Self.makeCGImage())
        let images = CountingImageGenerator(image: image)
        let pipeline = SeedPipeline(
            storyGenerator: storyGenerator,
            illustrationPrompts: illustrationPrompts,
            imageGenerator: images,
            photoDescriber: MockPhotoDescriber(),
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: root),
            bibleGenerator: bibleGenerator
        )
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let storyID = UUID()
        for await _ in pipeline.run(
            seed: seed,
            photo: PhotoDescribeInput(imageData: Data(repeating: 7, count: 64)),
            storyID: storyID
        ) {}

        // Extraction receives the description and the photo tags.
        XCTAssertEqual(bibleGenerator.descriptions, [seed.trimmed])
        XCTAssertEqual(bibleGenerator.receivedPhotoTags, ["child, brown hair, red coat, blue bicycle"])
        // The story is written from the bible block, not the raw tags.
        XCTAssertEqual(storyGenerator.receivedImageContexts, [bible.renderedBlock])
        // The illustration pass gets the bible block as hard requirements.
        XCTAssertEqual(illustrationPrompts.receivedElementsBlocks, [bible.renderedBlock])
        // The saved book persists the bible and the byte-stable lock.
        let saved = try XCTUnwrap(StoryFileStore(rootURL: root).loadStorybook(id: storyID))
        XCTAssertEqual(saved.bible, bible)
        XCTAssertEqual(saved.characterDescriptor, bible.characterLock)
    }

    func testBibleFailureFallsBackToRawTags() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bibleGenerator = RecordingBibleGenerator(bible: nil)
        let storyGenerator = MockStoryGenerator()
        let illustrationPrompts = MockIllustrationPrompts()
        let image = try XCTUnwrap(Self.makeCGImage())
        let images = CountingImageGenerator(image: image)
        let pipeline = SeedPipeline(
            storyGenerator: storyGenerator,
            illustrationPrompts: illustrationPrompts,
            imageGenerator: images,
            photoDescriber: MockPhotoDescriber(),
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: root),
            bibleGenerator: bibleGenerator
        )
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let storyID = UUID()
        for await _ in pipeline.run(
            seed: seed,
            photo: PhotoDescribeInput(imageData: Data(repeating: 7, count: 64)),
            storyID: storyID
        ) {}

        // The failed extraction degrades to today's raw-tag behavior.
        XCTAssertEqual(storyGenerator.receivedImageContexts, ["child, brown hair, red coat, blue bicycle"])
        XCTAssertEqual(illustrationPrompts.receivedElementsBlocks, ["child, brown hair, red coat, blue bicycle"])
        let saved = try XCTUnwrap(StoryFileStore(rootURL: root).loadStorybook(id: storyID))
        XCTAssertNil(saved.bible)
        XCTAssertEqual(saved.characterDescriptor, "orange kitten, round eyes")
        XCTAssertEqual(saved.phase, .finished)
    }

    func testLegacyStoryJSONWithoutBibleDecodes() throws {
        var book = Storybook(
            id: UUID(),
            title: "Lantern Garden",
            summary: "A kitten finds a lantern.",
            language: "en-US",
            seedPrompt: "a brave kitten finds a lantern",
            characterDescriptor: "orange kitten, round eyes",
            bible: StoryBible(characterLock: "orange kitten, round eyes"),
            baseSeed: 7,
            phase: .pages,
            pages: []
        )
        let data = try JSONEncoder().encode(book)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "bible") // a book written before the bible pass
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Storybook.self, from: legacy)
        XCTAssertNil(decoded.bible)
        book.bible = nil
        XCTAssertEqual(decoded, book)
    }

    func testBibleGeneratorRepairsMissingLockOnly() async throws {
        let completer = ScriptedCompleter(replies: [
            "SETTING: a quiet attic at night",
            "CHARACTER: brave bunny, white fur, blue scarf",
        ])
        let generator = DeviceStoryBibleGenerator(completer: completer)
        let bible = try await generator.generate(
            description: "a brave bunny finds a lantern",
            photoTags: nil
        )
        XCTAssertEqual(bible.characterLock, "brave bunny, white fur, blue scarf")
        XCTAssertEqual(bible.setting, "a quiet attic at night")
        XCTAssertEqual(completer.prompts.count, 2)
        XCTAssertTrue(completer.prompts[1].contains("CHARACTER:"))
    }

    func testBibleGeneratorThrowsWhenLockStillMissing() async {
        let completer = ScriptedCompleter(replies: [
            "SETTING: a quiet attic at night",
            "PROPS: red rose",
        ])
        let generator = DeviceStoryBibleGenerator(completer: completer)
        do {
            _ = try await generator.generate(
                description: "a brave bunny finds a lantern",
                photoTags: nil
            )
            XCTFail("expected missingCharacterLock")
        } catch let error as StoryBibleError {
            XCTAssertEqual(error, .missingCharacterLock)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func makePipeline(
        storeRoot: URL = FileManager.default.temporaryDirectory,
        images: CountingImageGenerator? = nil,
        bibleGenerator: (any StoryBibleGenerating)? = nil
    ) -> SeedPipeline {
        let image = images ?? CountingImageGenerator(image: Self.makeCGImage()!)
        return SeedPipeline(
            storyGenerator: MockStoryGenerator(),
            illustrationPrompts: MockIllustrationPrompts(),
            imageGenerator: image,
            photoDescriber: nil,
            memory: NoopMemory(),
            store: StoryFileStore(rootURL: storeRoot),
            bibleGenerator: bibleGenerator
        )
    }

    private static func makeCGImage() -> CGImage? {
        solidImage(red: 1, green: 0.6, blue: 0.2)
    }

    private static func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()
    }
}

private final class MockStoryGenerator: StoryFromPromptGenerating, @unchecked Sendable {
    private(set) var receivedImageContexts: [String?] = []
    func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        receivedImageContexts.append(prompt.imageContext)
        return StoryDraft(
            title: "Lantern Garden",
            summary: "A kitten finds a lantern.",
            seedPrompt: prompt.trimmed,
            paragraphs: (1...10).map { "Paragraph \($0) of the bedtime story." },
            language: prompt.language
        )
    }
}

private final class MockIllustrationPrompts: IllustrationPromptGenerating, @unchecked Sendable {
    private(set) var receivedElementsBlocks: [String] = []
    func generate(draftTitle: String, paragraphs: [String], elementsBlock: String) async throws -> IllustrationPlan {
        receivedElementsBlocks.append(elementsBlock)
        return IllustrationPlan(
            characterDescriptor: "orange kitten, round eyes",
            prompts: (1...10).map { "page \($0) garden lantern scene" }
        )
    }
}

private struct FailingIllustrationPrompts: IllustrationPromptGenerating {
    func generate(draftTitle: String, paragraphs: [String], elementsBlock: String) async throws -> IllustrationPlan {
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
    private let varied: Bool
    private let failSeeds: Set<UInt32>
    private(set) var calls = 0
    private(set) var modes: [ImageGenMode] = []
    private(set) var inputs: [Data] = []
    private(set) var strengths: [Float] = []
    private(set) var receivedNonEmptyImage = false
    init(image: CGImage, varied: Bool = false, failSeeds: Set<UInt32> = []) {
        self.image = image
        self.varied = varied
        self.failSeeds = failSeeds
    }
    func generate(_ input: ImageGenInput, config: ImageGenConfig) async throws -> ImageGenResult {
        calls += 1
        modes.append(config.mode)
        inputs.append(input.imageData)
        strengths.append(config.strength)
        if !input.isEmpty { receivedNonEmptyImage = true }
        if let seed = config.seed, failSeeds.contains(seed) {
            throw ImageGenError.generationFailed
        }
        let output = varied
            ? try XCTUnwrap(Self.solidImage(red: CGFloat(calls) / 12, green: 0.5, blue: 0.5))
            : image
        return ImageGenResult(cgImage: output, seed: config.seed ?? 0, elapsedSeconds: 0, bucket: .square)
    }

    static func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()
    }
}

private final class ScriptedCompleter: IllustrationPromptCompleting, @unchecked Sendable {
    let replies: [String]
    private(set) var prompts: [String] = []
    init(replies: [String]) { self.replies = replies }
    func complete(_ prompt: String) async throws -> String {
        prompts.append(prompt)
        return replies[min(prompts.count - 1, replies.count - 1)]
    }
}

private final class RecordingBibleGenerator: StoryBibleGenerating, @unchecked Sendable {
    let bible: StoryBible?
    private(set) var descriptions: [String] = []
    private(set) var receivedPhotoTags: [String?] = []
    init(bible: StoryBible?) { self.bible = bible }
    func generate(description: String, photoTags: String?) async throws -> StoryBible {
        descriptions.append(description)
        receivedPhotoTags.append(photoTags)
        guard let bible else { throw StoryBibleError.missingCharacterLock }
        return bible
    }
}

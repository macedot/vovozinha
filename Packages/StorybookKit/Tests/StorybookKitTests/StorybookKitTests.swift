import XCTest
import StoryPromptKit
import VovoUI
@testable import StorybookKit

final class StorybookKitTests: XCTestCase {

    func testStoryHistoryPersistsUpdatesAndDeletes() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let page = StoryPage(index: 1, text: "A quiet night.")
        let story = Storybook(
            id: id,
            title: "The Quiet Night",
            summary: "A gentle bedtime story.",
            language: "en-US",
            seedPrompt: "a quiet night in a glowing garden",
            phase: .story,
            pages: [page]
        )
        let store = StoryHistoryStore(rootURL: root)

        try store.upsert(story)
        XCTAssertEqual(try store.load().first?.title, "The Quiet Night")

        var finished = story
        finished.phase = .finished
        try store.upsert(finished)
        XCTAssertEqual(try store.load().first?.phase, .finished)

        try store.delete(finished)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testStorybookJSONRoundTripAndDelete() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StoryFileStore(rootURL: root)
        let id = UUID()
        let book = Storybook(
            id: id,
            title: "Lantern Garden",
            summary: "A kitten finds a lantern.",
            language: "pt-BR",
            seedPrompt: "um gato corajoso acha uma lanterna no jardim",
            phase: .finished,
            pages: (1...10).map { StoryPage(index: $0, text: "Página \($0).") }
        )

        try store.saveStorybook(book)
        let loaded = try XCTUnwrap(store.loadStorybook(id: id))
        XCTAssertEqual(loaded, book)

        try store.deleteStory(id: id)
        XCTAssertNil(store.loadStorybook(id: id))
    }

    func testLoadAllSkipsDirectoriesWithoutStoryJSON() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StoryFileStore(rootURL: root)
        let book = Storybook(
            id: UUID(),
            title: "Lantern Garden",
            summary: "",
            language: "en-US",
            seedPrompt: "a brave kitten finds a lantern tonight",
            phase: .finished,
            pages: (1...10).map { StoryPage(index: $0, text: "Page \($0).") }
        )
        try store.saveStorybook(book)

        let emptyID = UUID()
        try FileManager.default.createDirectory(
            at: store.storyDirectory(id: emptyID),
            withIntermediateDirectories: true
        )

        let all = store.loadAllStorybooks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, book.id)
    }

    func testPipelineEmitsTenPagesThenFinished() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = makePipeline(storeRoot: root)
        let seed = StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
        let storyID = UUID()
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: seed, storyID: storyID) {
            events.append(event)
        }

        let ready = events.compactMap { event -> [StoryPage]? in
            if case .pageTextsReady(let pages, _, _) = event { return pages }
            return nil
        }
        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready.first?.count, 10)
        XCTAssertEqual(ready.first?.first?.text, "Paragraph 1 of the bedtime story.")
        XCTAssertEqual(events.last, .finished)
        XCTAssertTrue(events.contains(where: {
            if case .phaseChanged(.finished) = $0 { return true }
            return false
        }))
    }

    func testPipelineReceivesParentDescriptionAndLanguage() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let generator = MockStoryGenerator()
        let pipeline = makePipeline(storeRoot: root, generator: generator)
        let seed = StorySeedPrompt(
            text: "um gato corajoso acha uma lanterna no jardim hoje",
            language: .portugueseBrazil
        )
        for await _ in pipeline.run(seed: seed, storyID: UUID()) {}

        XCTAssertEqual(generator.receivedSeeds, [seed.trimmed])
        XCTAssertEqual(generator.receivedLanguages, [.portugueseBrazil])
    }

    func testPipelineFailsWhenFewerThanTenParagraphs() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let generator = MockStoryGenerator(paragraphs: 9)
        let pipeline = makePipeline(storeRoot: root, generator: generator)
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: makeSeed(), storyID: UUID()) {
            events.append(event)
        }

        XCTAssertFalse(events.contains(where: {
            if case .pageTextsReady = $0 { return true }
            return false
        }))
        guard case .failed = events.last else {
            return XCTFail("expected .failed, got \(String(describing: events.last))")
        }
    }

    func testPipelineFailsWhenGeneratorThrows() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        struct FailingGenerator: StoryFromPromptGenerating {
            func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
                throw StoryPromptError.generationFailed
            }
        }
        let pipeline = makePipeline(storeRoot: root, generator: FailingGenerator())
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: makeSeed(), storyID: UUID()) {
            events.append(event)
        }

        XCTAssertTrue(events.contains(where: {
            if case .failed = $0 { return true }
            return false
        }))
        guard case .failed = events.last else {
            return XCTFail("expected .failed, got \(String(describing: events.last))")
        }
    }

    /// Cancellation ends the stream quietly: no failure event, no book.
    func testPipelineCancellationFinishesWithoutFailureEvent() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        struct CancellingGenerator: StoryFromPromptGenerating {
            func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
                throw CancellationError()
            }
        }
        let pipeline = makePipeline(storeRoot: root, generator: CancellingGenerator())
        let storyID = UUID()
        var events: [PipelineEvent] = []
        for await event in pipeline.run(seed: makeSeed(), storyID: storyID) {
            events.append(event)
        }

        XCTAssertFalse(events.contains(where: {
            if case .failed = $0 { return true }
            return false
        }))
        XCTAssertFalse(events.contains(where: {
            if case .pageTextsReady = $0 { return true }
            return false
        }))
        XCTAssertNil(StoryFileStore(rootURL: root).loadStorybook(id: storyID))
    }

    func testPipelinePersistsStorybookAtMilestones() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StoryFileStore(rootURL: root)
        let pipeline = makePipeline(storeRoot: root)
        let storyID = UUID()
        for await _ in pipeline.run(seed: makeSeed(), storyID: storyID) {}

        let saved = try XCTUnwrap(store.loadStorybook(id: storyID))
        XCTAssertEqual(saved.phase, .finished)
        XCTAssertEqual(saved.pages.count, 10)
        XCTAssertEqual(saved.title, "Lantern Garden")
        XCTAssertEqual(saved.language, "en-US")
        XCTAssertEqual(
            saved.seedPrompt,
            "a brave kitten finds a lantern in the garden path tonight"
        )
    }

    // MARK: - Helpers

    private func makeSeed() -> StorySeedPrompt {
        StorySeedPrompt(
            text: "a brave kitten finds a lantern in the garden path tonight",
            language: .englishUS
        )
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePipeline(
        storeRoot: URL,
        generator: StoryFromPromptGenerating = MockStoryGenerator()
    ) -> SeedPipeline {
        SeedPipeline(
            storyGenerator: generator,
            store: StoryFileStore(rootURL: storeRoot)
        )
    }
}

private final class MockStoryGenerator: StoryFromPromptGenerating, @unchecked Sendable {
    private(set) var receivedSeeds: [String] = []
    private(set) var receivedLanguages: [AppLanguage] = []
    private let paragraphs: Int

    init(paragraphs: Int = 10) {
        self.paragraphs = paragraphs
    }

    func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        receivedSeeds.append(prompt.trimmed)
        receivedLanguages.append(prompt.language)
        return StoryDraft(
            title: "Lantern Garden",
            summary: "A kitten finds a lantern.",
            seedPrompt: prompt.trimmed,
            paragraphs: (1...paragraphs).map { "Paragraph \($0) of the bedtime story." },
            language: prompt.language
        )
    }
}

import Foundation
import StoryPromptKit

/// Turns the parent's description into a 10-page text storybook: one on-device
/// LLM pass, texts published the moment they exist, book persisted immediately.
public struct SeedPipeline: Sendable {
    public var storyGenerator: any StoryFromPromptGenerating
    public var store: StoryFileStore

    public init(
        storyGenerator: any StoryFromPromptGenerating,
        store: StoryFileStore
    ) {
        self.storyGenerator = storyGenerator
        self.store = store
    }

    public func run(
        seed: StorySeedPrompt,
        storyID: UUID = UUID()
    ) -> AsyncStream<PipelineEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await execute(
                        seed: seed,
                        storyID: storyID,
                        continuation: continuation
                    )
                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(message: String(describing: error)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(
        seed: StorySeedPrompt,
        storyID: UUID,
        continuation: AsyncStream<PipelineEvent>.Continuation
    ) async throws {
        try Task.checkCancellation()
        continuation.yield(.phaseChanged(.story))
        let draft = try await storyGenerator.generate(from: seed)
        guard draft.paragraphs.count == 10 else {
            throw StoryPromptError.generationFailed
        }

        // Story text is the product. Publish it so the reader opens right away.
        let pages = draft.paragraphs.enumerated().map { i, text in
            StoryPage(index: i + 1, text: text)
        }
        continuation.yield(.pageTextsReady(
            pages: pages,
            title: draft.title,
            summary: draft.summary
        ))

        var book = Storybook(
            id: storyID,
            title: draft.title,
            summary: draft.summary,
            language: seed.language.rawValue,
            seedPrompt: seed.trimmed,
            phase: .story,
            pages: pages
        )
        func persist(_ phase: PipelinePhase) {
            book.phase = phase
            do {
                try store.saveStorybook(book)
            } catch {
                #if DEBUG
                print("[SeedPipeline] story.json save failed: \(error)")
                #endif
            }
        }
        persist(.story)
        persist(.finished)
        continuation.yield(.phaseChanged(.finished))
    }
}

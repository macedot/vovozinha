import Foundation
import ImageGenKit
import PhotoDescribeKit
import StoryPromptKit
import VovoUI

public struct SeedPipeline: Sendable {
    public var storyGenerator: any StoryFromPromptGenerating
    public var illustrationPrompts: any IllustrationPromptGenerating
    public var imageGenerator: any ImageGenerating
    public var photoDescriber: (any PhotoDescribing)?
    public var memory: any MemorySequencing
    public var store: StoryFileStore
    public var stylePrefix: String
    public var negativePrompt: String

    public init(
        storyGenerator: any StoryFromPromptGenerating,
        illustrationPrompts: any IllustrationPromptGenerating,
        imageGenerator: any ImageGenerating,
        photoDescriber: (any PhotoDescribing)? = nil,
        memory: any MemorySequencing,
        store: StoryFileStore,
        stylePrefix: String = ImageGenTemplate.positive(for: .englishUS),
        negativePrompt: String = ImageGenTemplate.defaultNegativePrompt
    ) {
        self.storyGenerator = storyGenerator
        self.illustrationPrompts = illustrationPrompts
        self.imageGenerator = imageGenerator
        self.photoDescriber = photoDescriber
        self.memory = memory
        self.store = store
        self.stylePrefix = stylePrefix
        self.negativePrompt = negativePrompt
    }

    public func run(
        seed: StorySeedPrompt,
        photo: PhotoDescribeInput?,
        storyID: UUID = UUID()
    ) -> AsyncStream<PipelineEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await execute(
                        seed: seed,
                        photo: photo,
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
        photo: PhotoDescribeInput?,
        storyID: UUID,
        continuation: AsyncStream<PipelineEvent>.Continuation
    ) async throws {
        try Task.checkCancellation()
        let totalSteps = 10
        var step = 0
        func tick() {
            step += 1
            continuation.yield(.progress(step: step, of: totalSteps))
        }

        continuation.yield(.phaseChanged(.caption))
        var captionText: String?
        if let photo, let describer = photoDescriber {
            let caption = try await describer.describe(photo, language: seed.language)
            captionText = caption.text
        }

        try Task.checkCancellation()
        continuation.yield(.phaseChanged(.story))
        var seeded = seed
        seeded.imageContext = captionText
        let draft = try await storyGenerator.generate(from: seeded)
        guard draft.paragraphs.count == 10 else {
            throw StoryPromptError.generationFailed
        }

        // Story text is the product. Publish it before the second LLM pass so a
        // CHARACTER:/numbered-line parse miss cannot hide the book.
        var pages = zip(draft.paragraphs.indices, draft.paragraphs).map { i, text in
            StoryPage(index: i + 1, text: text, illustrationPrompt: scenePrompt(from: text))
        }
        continuation.yield(.pageTextsReady(
            pages: pages,
            title: draft.title,
            summary: draft.summary
        ))

        try Task.checkCancellation()
        continuation.yield(.phaseChanged(.illustrationPrompts))
        var characterDescriptor = characterLock(from: captionText)
        do {
            let plan = try await illustrationPrompts.generate(
                draftTitle: draft.title,
                paragraphs: draft.paragraphs,
                caption: captionText
            )
            if plan.prompts.count == pages.count {
                characterDescriptor = plan.characterDescriptor
                for i in pages.indices {
                    pages[i].illustrationPrompt = plan.prompts[i]
                }
            }
        } catch {
            #if DEBUG
            print("[SeedPipeline] illustration prompts failed (\(error)); using paragraph scenes")
            #endif
        }
        tick()

        try Task.checkCancellation()
        await memory.releaseMLX()
        try await memory.prepareCoreML()

        continuation.yield(.phaseChanged(.pages))
        // Cover first (page 1), then 2...10. txt2img only — photo is never an img2img base.
        let order = [1] + Array(2...10)
        for index in order {
            try Task.checkCancellation()
            let fileName = store.pageFileName(index: index)
            if store.pngExists(id: storyID, fileName: fileName) {
                pages[index - 1].imageFileName = fileName
                continuation.yield(.illustrationReady(index: index, fileName: fileName))
                tick()
                continue
            }
            let page = pages[index - 1]
            let prompt = clipPrompt(scene: page.illustrationPrompt, lock: characterDescriptor)
            let config = ImageGenConfig(
                seed: StoryIdentity.pageSeed(storyID: storyID, pageIndex: index),
                mode: .textToImage,
                prompt: prompt,
                negativePrompt: negativePrompt
            )
            do {
                let result = try await imageGenerator.generate(
                    ImageGenInput(imageData: Data()),
                    config: config
                )
                _ = try store.writePNG(result.cgImage, id: storyID, fileName: fileName)
                pages[index - 1].imageFileName = fileName
                continuation.yield(.illustrationReady(index: index, fileName: fileName))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                #if DEBUG
                print("[SeedPipeline] page \(index) render failed: \(error)")
                #endif
            }
            tick()
        }

        await memory.releaseCoreML()
        continuation.yield(.phaseChanged(.finished))
    }

    /// CLIP 77-token budget: unique scene first, then short lock, then style.
    func clipPrompt(scene: String, lock: String) -> String {
        let lockBit = lock.split(separator: " ").prefix(20).joined(separator: " ")
        return [scene, lockBit, stylePrefix]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Scene fallback when the illustration LLM pass fails — the paragraph itself, not invented copy.
    func scenePrompt(from paragraph: String) -> String {
        paragraph.split(whereSeparator: \.isWhitespace).prefix(24).joined(separator: " ")
    }

    func characterLock(from caption: String?) -> String {
        let words = (caption ?? "")
            .split(whereSeparator: \.isWhitespace)
            .prefix(20)
            .joined(separator: " ")
        if words.isEmpty {
            return "cute kids-book hero, round face, bright clothes"
        }
        return words
    }
}

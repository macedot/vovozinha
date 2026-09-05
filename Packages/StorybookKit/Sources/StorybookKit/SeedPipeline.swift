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
        let totalSteps = 11 // 1 reference + 10 pages
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

        // The book is saved (texts only) the moment it exists, then re-saved on
        // every milestone so an interrupted run never loses what was generated.
        var book = Storybook(
            id: storyID,
            title: draft.title,
            summary: draft.summary,
            language: seed.language.rawValue,
            seedPrompt: seed.trimmed,
            characterDescriptor: characterLock(from: captionText),
            baseSeed: StoryIdentity.baseSeed(storyID: storyID),
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
        book.characterDescriptor = characterDescriptor
        book.pages = pages
        persist(.illustrationPrompts)

        try Task.checkCancellation()
        await memory.releaseMLX()
        try await memory.prepareCoreML()

        // One image every page inherits its cast from: the photo cartoonified at
        // high strength when a photo was provided, else a txt2img character sheet
        // at the story's base seed (invariant 9). A broken reference never kills
        // the book — pages then fall back to txt2img.
        continuation.yield(.phaseChanged(.reference))
        let referenceData = try await ensureReference(
            storyID: storyID,
            photo: photo,
            lock: characterDescriptor
        )
        tick()

        continuation.yield(.phaseChanged(.pages))
        // Cover first (page 1), then 2...10. Pages img2img from the reference so
        // the cast stays recognizable; txt2img fallback when no reference exists.
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
            let input: ImageGenInput
            let config: ImageGenConfig
            if let referenceData {
                input = ImageGenInput(imageData: referenceData)
                config = ImageGenConfig(
                    strength: Self.pageStrength,
                    seed: StoryIdentity.pageSeed(storyID: storyID, pageIndex: index),
                    mode: .imageToImage,
                    prompt: prompt,
                    negativePrompt: negativePrompt
                )
            } else {
                input = ImageGenInput(imageData: Data())
                config = ImageGenConfig(
                    strength: Self.pageStrength,
                    seed: StoryIdentity.pageSeed(storyID: storyID, pageIndex: index),
                    mode: .textToImage,
                    prompt: prompt,
                    negativePrompt: negativePrompt
                )
            }
            do {
                let result = try await imageGenerator.generate(input, config: config)
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
            book.pages = pages
            persist(.pages)
            tick()
        }

        await memory.releaseCoreML()
        persist(.finished)
        continuation.yield(.phaseChanged(.finished))
    }

    // MARK: - Reference pass (cast coherence)

    /// img2img strength for the photo → cartoon-reference pass. High on purpose:
    /// sheds photoreal residue (kids-safe, no real faces) while keeping the photo's
    /// cast elements (§12.21).
    static let referenceStrength: Float = 0.75
    /// img2img strength for page passes: low enough to keep the cast recognizable,
    /// high enough for scene composition to follow the page prompt (§12.4).
    static let pageStrength: Float = 0.5

    /// Returns the reference PNG bytes, rendering them once if missing. `nil` when
    /// rendering failed — callers fall back to txt2img pages. Cancellation throws.
    private func ensureReference(
        storyID: UUID,
        photo: PhotoDescribeInput?,
        lock: String
    ) async throws -> Data? {
        let fileName = StoryFileStore.referenceFileName
        if store.pngExists(id: storyID, fileName: fileName) {
            return try? Data(
                contentsOf: store.storyDirectory(id: storyID).appendingPathComponent(fileName)
            )
        }
        let prompt = clipPrompt(
            scene: "character reference sheet, full body, standing, front view",
            lock: lock
        )
        let seed = StoryIdentity.baseSeed(storyID: storyID)
        if let photo, !photo.isEmpty {
            let config = ImageGenConfig(
                strength: Self.referenceStrength,
                seed: seed,
                mode: .imageToImage,
                prompt: prompt,
                negativePrompt: negativePrompt
            )
            do {
                let result = try await imageGenerator.generate(
                    ImageGenInput(imageData: photo.imageData),
                    config: config
                )
                _ = try store.writePNG(result.cgImage, id: storyID, fileName: fileName)
                return try? Data(
                    contentsOf: store.storyDirectory(id: storyID).appendingPathComponent(fileName)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                #if DEBUG
                print("[SeedPipeline] photo reference failed (\(error)); txt2img fallback")
                #endif
            }
        }
        let config = ImageGenConfig(
            strength: Self.referenceStrength,
            seed: seed,
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
            return try? Data(
                contentsOf: store.storyDirectory(id: storyID).appendingPathComponent(fileName)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[SeedPipeline] reference render failed: \(error)")
            #endif
            return nil
        }
    }

    /// CLIP 77-token budget, enforced hard: nothing may truncate, so the lock and
    /// the style core stay byte-identical on every page. Assembly order — unique
    /// scene, short identity lock, compressed style core. Overflow eats the scene
    /// first, then the lock; the style core is never cut.
    func clipPrompt(scene: String, lock: String) -> String {
        let styleCore = Self.words(in: stylePrefix, limit: Self.styleWordLimit)
        var lockBit = Self.words(in: lock, limit: Self.lockWordLimit)
        var sceneBit = Self.words(in: scene, limit: Self.sceneWordLimit)
        while Self.wordCount([sceneBit, lockBit, styleCore]) > Self.totalWordBudget {
            if sceneBit.split(separator: " ").count > Self.minSceneWords {
                sceneBit = Self.words(in: sceneBit, limit: sceneBit.split(separator: " ").count - 1)
            } else if lockBit.split(separator: " ").count > Self.minLockWords {
                lockBit = Self.words(in: lockBit, limit: lockBit.split(separator: " ").count - 1)
            } else {
                break
            }
        }
        return [sceneBit, lockBit, styleCore]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    // MARK: - Prompt budget

    /// ~50 words ≈ ≤68 CLIP tokens — safety margin under the 75-token cut.
    static let totalWordBudget = 50
    static let styleWordLimit = 15
    static let lockWordLimit = 15
    static let sceneWordLimit = 20
    static let minSceneWords = 6
    static let minLockWords = 4

    static func words(in text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        return text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
    }

    static func wordCount(_ parts: [String]) -> Int {
        parts.reduce(0) { $0 + $1.split(separator: " ").count }
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

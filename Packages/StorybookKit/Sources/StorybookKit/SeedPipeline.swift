import Foundation
import ImageGenKit
import PhotoDescribeKit
import StoryPromptKit
import VovoUI

public struct SeedPipeline: Sendable {
    public var storyGenerator: any StoryFromPromptGenerating
    public var bibleGenerator: (any StoryBibleGenerating)?
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
        negativePrompt: String = ImageGenTemplate.defaultNegativePrompt,
        bibleGenerator: (any StoryBibleGenerating)? = nil
    ) {
        self.storyGenerator = storyGenerator
        self.illustrationPrompts = illustrationPrompts
        self.imageGenerator = imageGenerator
        self.photoDescriber = photoDescriber
        self.memory = memory
        self.store = store
        self.stylePrefix = stylePrefix
        self.negativePrompt = negativePrompt
        self.bibleGenerator = bibleGenerator
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
        var photoTags: String?
        if let photo, let describer = photoDescriber {
            let caption = try await describer.describe(photo, language: seed.language)
            photoTags = caption.text
        }

        // Story bible: fuse the description with the photo tags into the global
        // cast/world/props every later pass must obey. Extraction failing never
        // blocks the book — later passes fall back to raw tags or imagined cast.
        try Task.checkCancellation()
        continuation.yield(.phaseChanged(.bible))
        var bible: StoryBible?
        if let bibleGenerator {
            do {
                bible = try await bibleGenerator.generate(description: seed.trimmed, photoTags: photoTags)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                #if DEBUG
                print("[SeedPipeline] bible extraction failed (\(error)); falling back to raw tags")
                #endif
            }
        }

        try Task.checkCancellation()
        continuation.yield(.phaseChanged(.story))
        var seeded = seed
        seeded.imageContext = bible?.renderedBlock ?? photoTags
        let draft = try await storyGenerator.generate(from: seeded)
        guard draft.paragraphs.count == 10 else {
            throw StoryPromptError.generationFailed
        }

        // Story text is the product. Publish it before the second LLM pass so a
        // CHARACTER:/numbered-line parse miss cannot hide the book.
        var pages = zip(draft.paragraphs.indices, draft.paragraphs).map { i, text in
            StoryPage(
                index: i + 1,
                text: text,
                illustrationPrompt: scenePrompt(setting: bible?.setting ?? "")
            )
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
            characterDescriptor: bible?.characterLock ?? characterLock(from: photoTags),
            bible: bible,
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
        // The bible lock wins when present — it must stay byte-identical on every
        // page even if the illustration pass paraphrases its CHARACTER line.
        var characterDescriptor = bible?.characterLock ?? characterLock(from: photoTags)
        do {
            let plan = try await illustrationPrompts.generate(
                draftTitle: draft.title,
                paragraphs: draft.paragraphs,
                elementsBlock: bible?.renderedBlock ?? (photoTags ?? "")
            )
            if plan.prompts.count == pages.count {
                characterDescriptor = bible?.characterLock ?? plan.characterDescriptor
                for i in pages.indices {
                    pages[i].illustrationPrompt = plan.prompts[i]
                }
            }
        } catch {
            #if DEBUG
            print("[SeedPipeline] illustration prompts failed (\(error)); using English scene fallback")
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
        // Scene first, identity second. A page that re-mentions a supporting
        // cast member chains from the previous good page so that figure persists.
        // Recurring props travel as prompt words, not pixels — otherwise a bible
        // rose on every line recreates full-book chaining. Fresh scenes: photo
        // books img2img the cartoonified reference at high strength (face traces
        // remain, pose/place can change); no-photo books txt2img so the standing
        // character sheet cannot lock composition. A failed page leaves
        // `lastRendered` untouched — a later carry page chains from the newest
        // good page.
        let hasPhotoBase = photo.map { !$0.isEmpty } ?? false
        let order = [1] + Array(2...10)
        var lastRendered: (index: Int, data: Data)?
        for index in order {
            try Task.checkCancellation()
            let fileName = store.pageFileName(index: index)
            if store.pngExists(id: storyID, fileName: fileName) {
                pages[index - 1].imageFileName = fileName
                if let data = try? Data(
                    contentsOf: store.storyDirectory(id: storyID).appendingPathComponent(fileName)
                ) {
                    lastRendered = (index, data)
                }
                continuation.yield(.illustrationReady(index: index, fileName: fileName))
                tick()
                continue
            }
            let page = pages[index - 1]
            let prompt = clipPrompt(scene: page.illustrationPrompt, lock: characterDescriptor)
            var shared: [String] = []
            if index > 1, let lastRendered {
                shared = Self.sharedElements(
                    bible: bible,
                    pages[lastRendered.index - 1].illustrationPrompt,
                    page.illustrationPrompt
                )
            }
            let base: (data: Data, strength: Float)?
            if let lastRendered, !shared.isEmpty {
                base = (lastRendered.data, Self.carryStrength)
            } else if hasPhotoBase, let referenceData {
                base = (referenceData, index == 1 ? Self.coverStrength : Self.freshStrength)
            } else {
                base = nil
            }
            #if DEBUG
            print("[SeedPipeline] page \(index) prompt: \(prompt)")
            if !shared.isEmpty {
                print("[SeedPipeline] page \(index) carries: \(shared.joined(separator: ", "))")
            }
            #endif
            let input = ImageGenInput(imageData: base?.data ?? Data())
            let config = ImageGenConfig(
                strength: base?.strength ?? Self.freshStrength,
                guidanceScale: Self.pageGuidance,
                seed: StoryIdentity.pageSeed(storyID: storyID, pageIndex: index),
                mode: base == nil ? .textToImage : .imageToImage,
                prompt: prompt,
                negativePrompt: pageNegativePrompt()
            )
            do {
                let result = try await imageGenerator.generate(input, config: config)
                _ = try store.writePNG(result.cgImage, id: storyID, fileName: fileName)
                pages[index - 1].imageFileName = fileName
                // Chain from the persisted PNG, not an in-memory copy.
                if let data = try? Data(
                    contentsOf: store.storyDirectory(id: storyID).appendingPathComponent(fileName)
                ) {
                    lastRendered = (index, data)
                }
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

    /// img2img strength for the photo → cartoon-reference pass. Just under the
    /// old 0.75: keeps more of the real person's face/hair structure so the cast
    /// resembles the photo, while the locked negative + anime style scaffold shed
    /// photoreal residue (kids-safe, §12.21).
    static let referenceStrength: Float = 0.68
    /// img2img strength for the photo-path cover: high enough that the standing
    /// reference sheet cannot keep its pose, low enough that face/hair traces remain.
    static let coverStrength: Float = 0.88
    /// img2img strength when a supporting-cast member is re-mentioned: the figure
    /// persists from the previous good page while the new action still leads.
    static let carryStrength: Float = 0.82
    /// img2img strength for a photo-path page that opens a new scene. Same band
    /// as the cover — the cartoonified reference is a likeness hint, not a pose.
    static let freshStrength: Float = 0.88
    /// Prepended on page renders (not the reference pass) so leftover sheet
    /// composition loses the CLIP-negative race. Negative also truncates at 77
    /// tokens, so these have to lead.
    static let pageNegativePrefix =
        "character sheet, reference sheet, standing pose, front view, plain background, white background, character design"
    /// CFG for page renders: above the 6.0 default so the page prompt pulls
    /// harder than the chained base image (text adherence on SD 1.5).
    static let pageGuidance: Float = 7.5

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
            // One figure, plain background — "character reference sheet" invites
            // multi-view grids that dilute the person's identity.
            scene: "single character design, one full body figure, standing, front view, plain background",
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

    /// CLIP 77-token budget, enforced hard. Assembly order — unique scene, short
    /// identity lock, compressed style core. Overflow eats style first, then the
    /// lock; the scene is the last thing cut, because that is the page description.
    func clipPrompt(scene: String, lock: String) -> String {
        var styleCore = Self.words(in: stylePrefix, limit: Self.styleWordLimit)
        var lockBit = Self.words(in: lock, limit: Self.lockWordLimit)
        var sceneBit = Self.words(in: scene, limit: Self.sceneWordLimit)
        while Self.wordCount([sceneBit, lockBit, styleCore]) > Self.totalWordBudget {
            if styleCore.split(separator: " ").count > Self.minStyleWords {
                styleCore = Self.words(in: styleCore, limit: styleCore.split(separator: " ").count - 1)
            } else if lockBit.split(separator: " ").count > Self.minLockWords {
                lockBit = Self.words(in: lockBit, limit: lockBit.split(separator: " ").count - 1)
            } else if sceneBit.split(separator: " ").count > Self.minSceneWords {
                sceneBit = Self.words(in: sceneBit, limit: sceneBit.split(separator: " ").count - 1)
            } else {
                break
            }
        }
        return [sceneBit, lockBit, styleCore]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Page renders fight leftover character-sheet composition; the reference
    /// pass keeps the locked kids negative as-is.
    func pageNegativePrompt() -> String {
        [Self.pageNegativePrefix, negativePrompt]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    // MARK: - Prompt budget

    /// ~50 words ≈ ≤68 CLIP tokens — safety margin under the 75-token cut.
    /// Rebalanced toward the scene: the rewritten style scaffold carries the
    /// child look in 12 words, freeing 3 words for concrete scene detail.
    static let totalWordBudget = 50
    static let styleWordLimit = 12
    static let lockWordLimit = 15
    static let sceneWordLimit = 23
    static let minSceneWords = 6
    static let minLockWords = 4
    static let minStyleWords = 4

    static func words(in text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        return text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
    }

    static func wordCount(_ parts: [String]) -> Int {
        parts.reduce(0) { $0 + $1.split(separator: " ").count }
    }

    // MARK: - Continuity

    /// Supporting-cast phrases present in BOTH scene lines — the only reason a
    /// page inherits the previous page's pixels. Props stay as prompt words so a
    /// bible rose on every line cannot recreate full-book chaining. The main
    /// character is excluded: their identity travels in the prompt lock. Matching
    /// is whole-word (`cat` does not match `catch`).
    static func sharedElements(bible: StoryBible?, _ previous: String, _ next: String) -> [String] {
        guard let bible, !previous.isEmpty, !next.isEmpty else { return [] }
        let previousTokens = wholeWords(in: previous)
        let nextTokens = wholeWords(in: next)
        let supporting = bible.supporting
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "(none)" }
        return supporting.filter { phrase in
            containsWholePhrase(phrase, in: previousTokens)
                && containsWholePhrase(phrase, in: nextTokens)
        }
    }

    static func wholeWords(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func containsWholePhrase(_ phrase: String, in tokens: [String]) -> Bool {
        let words = wholeWords(in: phrase)
        guard !words.isEmpty, words.count <= tokens.count else { return false }
        let last = tokens.count - words.count
        for i in 0...last {
            if Array(tokens[i..<(i + words.count)]) == words { return true }
        }
        return false
    }

    /// Scene fallback when the illustration LLM pass fails — English setting
    /// (or a generic scene). Never the story-language paragraph: CLIP is
    /// English-only. The character lock is appended separately by `clipPrompt`.
    func scenePrompt(setting: String) -> String {
        let place = setting.trimmingCharacters(in: .whitespaces)
        if place.isEmpty || place == "(none)" {
            return "bedtime picture book scene"
        }
        return Self.words(in: place, limit: Self.sceneWordLimit)
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

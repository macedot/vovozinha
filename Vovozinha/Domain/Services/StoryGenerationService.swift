import Foundation
import SwiftData
import UIKit
import Observation

enum GenerationStage: Equatable, Sendable {
    case idle
    case analyzingCharacter
    case planningStory
    case illustrating(page: Int, total: Int) // unused when FeatureFlags.graphicsEnabled == false
    case saving
    case finished
    case failed(String)

    var progress: Double {
        // TEXT_ONLY_PHASE: no illustration slice of the progress bar.
        if !FeatureFlags.graphicsEnabled {
            switch self {
            case .idle: return 0
            case .analyzingCharacter: return 0.2
            case .planningStory: return 0.65
            case .saving: return 0.9
            case .finished: return 1
            case .illustrating: return 0.7
            case .failed: return 0
            }
        }
        switch self {
        case .idle: return 0
        case .analyzingCharacter: return 0.12
        case .planningStory: return 0.28
        case .illustrating(let page, let total):
            let t = max(total, 1)
            return 0.28 + 0.6 * (Double(page) / Double(t))
        case .saving: return 0.95
        case .finished: return 1
        case .failed: return 0
        }
    }
}

@MainActor
@Observable
final class StoryGenerationService {
    private let analyzer: any CharacterAnalyzing
    private let planner: any StoryPlanning
    private let illustrator: any Illustrating
    private let storage: FileStorage

    var stage: GenerationStage = .idle
    var deviceProfile: DeviceProfile = .current
    private(set) var lastStoryID: UUID?

    var isRunning: Bool {
        switch stage {
        case .idle, .finished, .failed: return false
        default: return true
        }
    }

    init(
        analyzer: any CharacterAnalyzing = MockCharacterAnalyzer(),
        planner: any StoryPlanning = FoundationModelsStoryPlanner(),
        illustrator: any Illustrating = ProceduralKidsIllustrator(),
        storage: FileStorage = .shared
    ) {
        self.analyzer = analyzer
        self.planner = planner
        self.illustrator = illustrator
        self.storage = storage
    }

    static func makeDefault(profile: DeviceProfile = .current) -> StoryGenerationService {
        // LLM only — never use pre-computed / template stories.
        let planner: any StoryPlanning = {
            switch profile.preferredStoryPlannerKind {
            case .foundationModels:
                return FoundationModelsStoryPlanner()
            case .localLLMPack:
                // Pack runtime not shipped yet; surface unavailability clearly.
                return UnavailableLLMStoryPlanner(reason: .llmUnavailable)
            case .none:
                return UnavailableLLMStoryPlanner(reason: .llmUnavailable)
            }
        }()

        return StoryGenerationService(
            analyzer: MockCharacterAnalyzer(),
            planner: planner,
            illustrator: IllustratorFactory.make(profile: profile)
        )
    }

    func generate(input: StoryDraftInput, modelContext: ModelContext) async throws -> Story {
        deviceProfile = .current

        guard deviceProfile.canGenerateStories else {
            let err = StoryPlanningError.llmUnavailable
            stage = .failed(err.localizedDescription(for: input.language))
            throw err
        }

        // Force 10-page text arc this phase.
        var draft = input
        draft.pageCount = FeatureFlags.fixedPageCount

        stage = .analyzingCharacter
        await Task.yield()
        let character: CharacterProfile
        do {
            character = try await analyzer.analyze(input: draft)
        } catch let analysis as CharacterAnalysisError {
            let msg = analysis.localizedDescription(for: draft.language)
            stage = .failed(msg)
            throw analysis
        } catch {
            let err = StoryPlanningError.from(systemError: error)
            stage = .failed(err.localizedDescription(for: draft.language))
            throw err
        }

        stage = .planningStory
        await Task.yield()
        let plan: StoryPlan
        do {
            plan = try await planner.plan(input: draft, character: character)
        } catch {
            // Map FM/context errors before they leak English into the UI.
            let err = StoryPlanningError.from(systemError: error)
            stage = .failed(err.localizedDescription(for: draft.language))
            throw err
        }

        let storyID = UUID()
        var pageModels: [StoryPage] = []
        var coverPath: String?

        // Offline page art: neural pack (Core ML SD) if installed, else procedural.
        // Temporal coherence: shared story seed + img2img / underlay from previous page.
        if deviceProfile.canRunGraphics {
            let total = plan.pages.count
            let storySeed = Self.makeStoryArtSeed(
                title: plan.title,
                character: plan.character.name,
                setting: plan.setting
            )
            var previousImage: UIImage?
            /// Page 0 establish frame — re-injected so actor design stays stable.
            var heroReferenceImage: UIImage?
            /// Cumulative lock: hero + world + every element that has appeared.
            var artMemory = StoryArtMemory.seed(
                character: plan.character,
                setting: plan.setting,
                artStyle: plan.artStyle
            )
            for page in plan.pages {
                stage = .illustrating(page: page.index + 1, total: total)
                await Task.yield()
                // Section-specific prompt + page text + growing continuity memory.
                let built = ScenePromptBuilder.brief(
                    pageText: page.text,
                    sceneTag: page.sceneTag,
                    character: plan.character,
                    setting: plan.setting,
                    artStyle: plan.artStyle,
                    language: draft.language,
                    pageIndex: page.index,
                    totalPages: total,
                    memory: artMemory
                )
                let brief = built.brief
                artMemory = built.memory
                // Page 0: establish. Later: enough img2img to keep designs, enough change for page text.
                let continuity: Float = page.index == 0 ? 0.0 : 0.50
                let request = IllustrationRequest(
                    page: page,
                    plan: plan,
                    referencePhoto: draft.photoData,
                    previousPageImage: previousImage,
                    heroReferenceImage: heroReferenceImage,
                    storySeed: storySeed,
                    pageSeed: storySeed &+ UInt64(page.index) &* 1_000_003,
                    continuityStrength: continuity,
                    brief: brief
                )
                let image: UIImage
                do {
                    image = try await illustrator.illustrate(request)
                } catch {
                    // Fail-soft: procedural path if primary fails mid-story.
                    image = (try? await ProceduralKidsIllustrator().illustrate(request))
                        ?? Self.fallbackIllustration(for: page, plan: plan)
                }
                if page.index == 0 {
                    heroReferenceImage = image
                }
                previousImage = image
                let fileName = String(format: "page_%02d.jpg", page.index)
                let path = try storage.saveImage(image, storyID: storyID, fileName: fileName)
                if page.index == 0 { coverPath = path }
                pageModels.append(
                    StoryPage(
                        index: page.index,
                        text: page.text,
                        imagePrompt: brief.positivePrompt,
                        imagePath: path
                    )
                )
            }
            // Free heavy Core ML weights after the story.
            CoreMLDiffusionIllustrator.unloadPipeline()
        } else {
            for page in plan.pages {
                pageModels.append(
                    StoryPage(
                        index: page.index,
                        text: page.text,
                        imagePrompt: page.imagePrompt,
                        imagePath: nil
                    )
                )
            }
        }

        stage = .saving
        await Task.yield()
        let story = Story(
            id: storyID,
            title: plan.title,
            summary: plan.summary,
            characterName: plan.character.name,
            characterAppearance: plan.character.appearance,
            setting: plan.setting,
            lesson: plan.lesson,
            ageBand: plan.ageBand,
            artStyle: plan.artStyle,
            childName: "",
            language: draft.language,
            coverImagePath: coverPath,
            pages: pageModels
        )

        modelContext.insert(story)
        try modelContext.save()

        lastStoryID = story.id
        stage = .finished
        await Task.yield()
        return story
    }

    func reset() {
        stage = .idle
        lastStoryID = nil
    }

    private static func makeStoryArtSeed(title: String, character: String, setting: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        let raw = "\(title)|\(character)|\(setting)|vovozinha-art"
        for b in raw.utf8 {
            h ^= UInt64(b)
            h = h &* 1099511628211
        }
        return h
    }

    /// Last-resort offline art if the illustrator throws.
    private static func fallbackIllustration(for page: StoryPlanPage, plan: StoryPlan) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor(red: 0.55, green: 0.70, blue: 0.95, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let label = "\(plan.title) · \(page.index + 1)" as NSString
            label.draw(
                in: CGRect(x: 48, y: size.height / 2 - 40, width: size.width - 96, height: 80),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
            )
        }
    }
}

import Foundation

/// Feature toggles for phased delivery.
enum FeatureFlags {
    /// Offline page art via `ProceduralKidsIllustrator` (scene-aware). Neural pack can replace later.
    static let graphicsEnabled = true

    /// Fixed narrative length for the text-quality phase.
    static let fixedPageCount = 10

    /// Target length for the whole story (all pages). Prompts aim near the middle of the band.
    static let targetStoryWordCount = 280
    /// Acceptable total word band after generation + repair (descriptive kids scenes).
    static let minStoryWordCount = 150
    static let maxStoryWordCount = 480

    /// How many times the on-device LLM may rewrite a story that fails `KidsSafetyFilter`
    /// before giving up. Generation retries until the story passes or this cap is hit.
    static let kidsFilterMaxAttempts = 12
}

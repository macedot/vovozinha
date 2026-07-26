import Foundation

struct StoryPlanPage: Codable, Hashable, Sendable, Identifiable {
    var id: Int { index }
    var index: Int
    var text: String
    /// Kept for a future local image pack even in text-only phase.
    var imagePrompt: String
    var narrationHint: String
    /// Ordered narrative beat: setup, explore, inciting, feel, plan, try, help, turn, lesson, bedtime.
    var sceneTag: String

    init(
        index: Int,
        text: String,
        imagePrompt: String,
        narrationHint: String,
        sceneTag: String = ""
    ) {
        self.index = index
        self.text = text
        self.imagePrompt = imagePrompt
        self.narrationHint = narrationHint
        self.sceneTag = sceneTag
    }
}

struct StoryPlan: Codable, Hashable, Sendable {
    var title: String
    var summary: String
    var character: CharacterProfile
    var setting: String
    var lesson: String
    var ageBand: AgeBand
    var artStyle: ArtStyle
    var pages: [StoryPlanPage]

    var pageCount: Int { pages.count }
}

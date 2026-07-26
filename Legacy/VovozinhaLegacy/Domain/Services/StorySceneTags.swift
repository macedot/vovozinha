import Foundation

/// Canonical temporal beat labels for a fixed 10-page kids arc.
/// One continuous story → exactly 10 paragraphs in this order (paragraph i = scene i).
enum StorySceneTags {
    static let ordered: [String] = [
        "setup", "explore", "inciting", "feel", "plan",
        "try", "help", "turn", "lesson", "bedtime"
    ]

    static var count: Int { ordered.count }

    /// English gloss for LLM prompts (from `Prompts/story/scene_list.txt`).
    static var promptSceneList: String {
        PromptCatalog.text("story/scene_list.txt")
    }

    static func tag(at index: Int) -> String {
        guard index >= 0, index < ordered.count else {
            return ordered.last ?? "story"
        }
        return ordered[index]
    }
}

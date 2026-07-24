import Foundation

/// Canonical temporal beat labels for a fixed 10-page kids arc.
/// Assigned in order after the LLM writes the continuous story (labels for future art / analytics only).
enum StorySceneTags {
    static let ordered: [String] = [
        "setup", "explore", "inciting", "feel", "plan",
        "try", "help", "turn", "lesson", "bedtime"
    ]

    static var count: Int { ordered.count }
}

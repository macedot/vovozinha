import Foundation

/// Fails fast when no on-device LLM is available (no template fallback).
struct UnavailableLLMStoryPlanner: StoryPlanning {
    var reason: StoryPlanningError = .llmUnavailable

    func plan(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan {
        throw reason
    }
}

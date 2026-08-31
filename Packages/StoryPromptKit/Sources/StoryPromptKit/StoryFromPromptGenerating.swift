import Foundation

/// Feature boundary: seed prompt → story draft (on-device LLM only).
public protocol StoryFromPromptGenerating: Sendable {
    func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft
}

public enum StoryPromptError: Error, Equatable, Sendable {
    case invalidPrompt(StorySeedPrompt.ValidationError)
    /// Model missing, inference failed, or unusable model output.
    case generationFailed
    /// On-device MLX story model pack is not installed yet.
    case modelNotInstalled
}

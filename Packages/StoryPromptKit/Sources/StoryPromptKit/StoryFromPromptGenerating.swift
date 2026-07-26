import Foundation

/// Feature boundary: seed prompt → story draft.
public protocol StoryFromPromptGenerating: Sendable {
    func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft
}

public enum StoryPromptError: Error, Equatable, Sendable {
    case invalidPrompt(StorySeedPrompt.ValidationError)
    case generationFailed
}

/// Offline deterministic generator for the multi-module bootstrap.
/// Later: swap for Foundation Models while keeping this protocol.
public struct OfflineStoryFromPromptGenerator: StoryFromPromptGenerating {
    public init() {}

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()
        try await Task.sleep(for: .milliseconds(250))

        let seed = prompt.trimmed
        let title = Self.makeTitle(from: seed)
        let summary = "A gentle bedtime story inspired by: \(seed)"
        let paragraphs = Self.makeParagraphs(seed: seed)

        return StoryDraft(
            title: title,
            summary: summary,
            seedPrompt: seed,
            paragraphs: paragraphs
        )
    }

    private static func makeTitle(from seed: String) -> String {
        let parts = seed.split(whereSeparator: \.isWhitespace).prefix(4).map(String.init)
        guard let first = parts.first else { return "Bedtime Story" }
        let head = first.prefix(1).uppercased() + first.dropFirst()
        let tail = parts.dropFirst().joined(separator: " ")
        return tail.isEmpty ? head : "\(head) \(tail)"
    }

    /// Ten short scene-shaped paragraphs; scene content follows the seed idea, not a forced cast.
    private static func makeParagraphs(seed: String) -> [String] {
        let idea = seed
        return [
            "Evening light softens the world. The idea of the story begins: \(idea). Everything feels calm and ready for a gentle adventure.",
            "A quiet path opens ahead. Soft colors and a mild breeze set the place. Curiosity grows without hurry.",
            "A small gentle problem appears, light enough for little hearts. Nothing scary—only a moment that needs kindness.",
            "Feelings settle like warm blankets. There is a little worry and a little courage, side by side.",
            "A kind plan takes shape. Simple steps, soft voices, and patience make the plan feel safe.",
            "The first careful try happens slowly. Hands and hearts work with care. Mistakes are allowed.",
            "A friendly help joins in. Together is easier. The place feels brighter for a moment.",
            "Things turn better. Smiles return. The air feels lighter, and hope is easy to hold.",
            "The lesson of the seed idea shines without a lecture—\(idea)—woven into a warm feeling.",
            "Night arrives softly. Stars wink like tiny lamps. It is time for sleep, dreams, and peace."
        ]
    }
}

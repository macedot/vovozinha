import Foundation

// MARK: - Character analyzer (description / photo → profile; no cloud)

/// Local placeholder until a vision model is available. Respects `input.language`.
struct MockCharacterAnalyzer: CharacterAnalyzing {
    func analyze(input: StoryDraftInput) async throws -> CharacterProfile {
        try await Task.sleep(for: .milliseconds(400))

        guard input.hasActorIdentity else {
            throw CharacterAnalysisError.missingInput
        }

        let lang = input.language
        let name = input.resolvedActorName()
        let desc = input.trimmedActorDescription

        if !desc.isEmpty {
            return CharacterProfile.fromManual(name: name, description: desc, language: lang)
        }

        if input.hasPhoto {
            let cute = CharacterProfile.defaultCuteAppearance(name: name, language: lang)
            return CharacterProfile(
                name: name.isEmpty ? CharacterProfile.defaultHeroName(lang) : name,
                appearance: cute.appearance,
                personality: CharacterProfile.defaultPersonality(lang),
                lockedDescription: cute.locked
            )
        }

        return CharacterProfile.fromManual(
            name: name,
            description: CharacterProfile.defaultNameOnlyDescription(name: name, language: lang),
            language: lang
        )
    }
}


// Procedural kids illustrator lives in ProceduralKidsIllustrator.swift

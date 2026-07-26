import Foundation
import UIKit

protocol CharacterAnalyzing: Sendable {
    func analyze(input: StoryDraftInput) async throws -> CharacterProfile
}

enum CharacterAnalysisError: LocalizedError, Equatable {
    case missingInput
    case failed

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Include the character: photo, name, or description."
        case .failed:
            return "Could not understand the character."
        }
    }

    func localizedDescription(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.missingInput, .portugueseBrazil):
            return "Inclua o personagem: foto, nome ou descrição."
        case (.missingInput, .englishUS):
            return errorDescription ?? "Missing input"
        case (.missingInput, .spanishSpain):
            return "Incluye el personaje: foto, nombre o descripción."
        case (.failed, .portugueseBrazil):
            return "Não foi possível entender o personagem."
        case (.failed, .englishUS):
            return errorDescription ?? "Failed"
        case (.failed, .spanishSpain):
            return "No se pudo entender el personaje."
        }
    }
}

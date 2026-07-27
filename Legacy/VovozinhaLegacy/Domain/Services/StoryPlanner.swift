import Foundation

protocol StoryPlanning: Sendable {
    func plan(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan
}

enum StoryPlanningError: LocalizedError, Equatable {
    case failed
    case unsafeContent
    case llmUnavailable
    /// On-device model session hit the context window; usually recovered with a fresh session.
    case contextExceeded

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Could not create the children's story with the on-device model."
        case .unsafeContent:
            return "Could not create a story that passed the children's content filter after several rewrites. Please try again."
        case .llmUnavailable:
            return "On-device LLM is not available. Stories require Apple Foundation Models (iOS 26+, Apple Intelligence enabled) or a local model pack. Pre-written templates are not used."
        case .contextExceeded:
            return "The on-device model ran out of space mid-generation. Please try again."
        }
    }

    func localizedDescription(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.failed, .portugueseBrazil):
            return "Não foi possível criar a história com o modelo no aparelho."
        case (.failed, .englishUS):
            return errorDescription ?? "Failed"
        case (.failed, .spanishSpain):
            return "No se pudo crear la historia con el modelo en el dispositivo."

        case (.unsafeContent, .portugueseBrazil):
            return "Não foi possível criar uma história que passasse no filtro infantil após várias tentativas. Tente de novo."
        case (.unsafeContent, .englishUS):
            return errorDescription ?? "Unsafe"
        case (.unsafeContent, .spanishSpain):
            return "No se pudo crear una historia que pasara el filtro infantil tras varios reintentos. Inténtalo de nuevo."

        case (.llmUnavailable, .portugueseBrazil):
            return "LLM no aparelho indisponível. As histórias exigem Apple Foundation Models (iOS 26+, Apple Intelligence) ou um pack de modelo local. Não usamos textos pré-prontos."
        case (.llmUnavailable, .englishUS):
            return errorDescription ?? "LLM unavailable"
        case (.llmUnavailable, .spanishSpain):
            return "LLM en el dispositivo no disponible. Las historias requieren Apple Foundation Models (iOS 26+, Apple Intelligence) o un pack de modelo local. No usamos textos preescritos."

        case (.contextExceeded, .portugueseBrazil):
            return "O modelo no aparelho ficou sem espaço durante a geração. Tente de novo."
        case (.contextExceeded, .englishUS):
            return errorDescription ?? "Context exceeded"
        case (.contextExceeded, .spanishSpain):
            return "El modelo en el dispositivo se quedó sin espacio durante la generación. Inténtalo de nuevo."
        }
    }

    /// UI-facing copy (localized). No static-story path to hide LLM unavailability.
    static func displayMessage(
        for error: Error,
        language: AppLanguage
    ) -> String {
        StoryPlanningError.from(systemError: error).localizedDescription(for: language)
    }

    /// True when the localized string is the product “LLM unavailable” copy (for tests).
    var isLLMUnavailableMessage: Bool {
        if case .llmUnavailable = self { return true }
        return false
    }

    /// Maps system / Foundation Models errors to localized app errors.
    /// Never pass raw English system strings into the UI.
    static func from(systemError error: Error) -> StoryPlanningError {
        if let planning = error as? StoryPlanningError {
            return planning
        }
        if error is CancellationError {
            return .failed
        }
        // Character analysis failures become a generic planning failure (localized in UI).
        if error is CharacterAnalysisError {
            return .failed
        }

        let text = [
            error.localizedDescription,
            String(describing: error),
            (error as NSError).domain,
            String((error as NSError).code)
        ].joined(separator: " ").lowercased()

        if text.contains("context")
            || text.contains("transcript")
            || (text.contains("token") && text.contains("exceed"))
            || text.contains("exceededcontextwindow")
            || text.contains("contextwindow")
            || text.contains("context size")
        {
            return .contextExceeded
        }

        if text.contains("not available")
            || text.contains("unavailable")
            || text.contains("apple intelligence")
            || text.contains("model is not")
        {
            return .llmUnavailable
        }

        return .failed
    }
}

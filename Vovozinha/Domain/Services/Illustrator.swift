import Foundation
import UIKit

protocol Illustrating: Sendable {
    func illustrate(
        page: StoryPlanPage,
        plan: StoryPlan,
        referencePhoto: Data?
    ) async throws -> UIImage
}

enum IllustrationError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Could not create the page illustration."
    }

    func localizedDescription(for language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil: return "Não foi possível criar a ilustração da página."
        case .englishUS: return errorDescription ?? "Failed"
        case .spanishSpain: return "No se pudo crear la ilustración de la página."
        }
    }
}

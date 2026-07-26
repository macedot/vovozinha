import Foundation

enum AgeBand: String, Codable, CaseIterable, Identifiable, Sendable {
    case threeToFive = "3-5"
    case sixToEight = "6-8"

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.threeToFive, .portugueseBrazil): return "3 a 5 anos"
        case (.threeToFive, .englishUS): return "Ages 3–5"
        case (.threeToFive, .spanishSpain): return "3 a 5 años"
        case (.sixToEight, .portugueseBrazil): return "6 a 8 anos"
        case (.sixToEight, .englishUS): return "Ages 6–8"
        case (.sixToEight, .spanishSpain): return "6 a 8 años"
        }
    }

    func subtitle(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.threeToFive, .portugueseBrazil): return "Frases curtas e bem suaves"
        case (.threeToFive, .englishUS): return "Very short, gentle sentences"
        case (.threeToFive, .spanishSpain): return "Frases cortas y muy suaves"
        case (.sixToEight, .portugueseBrazil): return "Aventura leve com um pouquinho mais de texto"
        case (.sixToEight, .englishUS): return "Light adventure with a bit more text"
        case (.sixToEight, .spanishSpain): return "Aventura suave con un poco más de texto"
        }
    }

    /// Hint for story generation length / vocabulary (descriptive scenes, still gentle).
    func generationHint(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.threeToFive, .portugueseBrazil):
            return "3 frases simples por página (com ponto). Descreva cores, sons e cheiros de forma carinhosa. ~25–35 palavras por página; história ~250–320 palavras."
        case (.threeToFive, .englishUS):
            return "3 simple sentences per page (with periods). Describe colors, sounds, and soft smells. ~25–35 words per page; whole story ~250–320 words."
        case (.threeToFive, .spanishSpain):
            return "3 frases simples por página (con punto). Describe colores, sonidos y olores suaves. ~25–35 palabras por página; historia ~250–320 palabras."
        case (.sixToEight, .portugueseBrazil):
            return "3 a 5 frases por página (com ponto). Cenas mais ricas: o que o herói vê, sente e faz. ~30–45 palavras por página; história ~280–400 palavras. Sem medo."
        case (.sixToEight, .englishUS):
            return "3 to 5 sentences per page (with periods). Richer scenes: what the hero sees, feels, and does. ~30–45 words per page; whole story ~280–400 words. No fear."
        case (.sixToEight, .spanishSpain):
            return "3 a 5 frases por página (con punto). Escenas más ricas: lo que el héroe ve, siente y hace. ~30–45 palabras por página; historia ~280–400 palabras. Sin miedo."
        }
    }
}

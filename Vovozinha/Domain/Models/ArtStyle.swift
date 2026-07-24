import Foundation

enum ArtStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case watercolor = "aquarela"
    case cartoon = "cartoon"
    case pastel = "pastel"

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.watercolor, .portugueseBrazil): return "Anime aquarela"
        case (.watercolor, .englishUS): return "Anime watercolor"
        case (.watercolor, .spanishSpain): return "Anime acuarela"
        case (.cartoon, .portugueseBrazil): return "Anime"
        case (.cartoon, .englishUS): return "Anime"
        case (.cartoon, .spanishSpain): return "Anime"
        case (.pastel, .portugueseBrazil): return "Anime pastel"
        case (.pastel, .englishUS): return "Anime pastel"
        case (.pastel, .spanishSpain): return "Anime pastel"
        }
    }

    /// English fragments only — image models are prompted in EN.
    func promptFragment(_ lang: AppLanguage) -> String {
        _ = lang
        switch self {
        case .watercolor:
            return """
            soft hand-painted Japanese anime still, watercolor and gouache anime backgrounds, \
            gentle brush texture, warm natural light, storybook anime composition
            """
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        case .cartoon:
            return """
            bright Japanese kids anime, clean cel shading, crisp linework, \
            cheerful anime character design, clear silhouettes, vibrant but soft colors
            """
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        case .pastel:
            return """
            soft pastel Japanese anime, gentle bedtime anime mood, muted dreamy palette, \
            soft cel shading, cozy night-story atmosphere
            """
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
    }
}

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

    /// English fragments only — image models are prompted in EN (`Prompts/art/style.*.txt`).
    func promptFragment(_ lang: AppLanguage) -> String {
        _ = lang
        switch self {
        case .watercolor:
            return PromptCatalog.text("art/style.watercolor.txt", collapseWhitespace: true)
        case .cartoon:
            return PromptCatalog.text("art/style.cartoon.txt", collapseWhitespace: true)
        case .pastel:
            return PromptCatalog.text("art/style.pastel.txt", collapseWhitespace: true)
        }
    }
}

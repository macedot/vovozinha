import Foundation

enum ArtStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case watercolor = "aquarela"
    case cartoon = "cartoon"
    case pastel = "pastel"

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.watercolor, .portugueseBrazil): return "Aquarela"
        case (.watercolor, .englishUS): return "Watercolor"
        case (.watercolor, .spanishSpain): return "Acuarela"
        case (.cartoon, .portugueseBrazil), (.cartoon, .englishUS), (.cartoon, .spanishSpain):
            return "Cartoon"
        case (.pastel, .portugueseBrazil), (.pastel, .englishUS): return "Pastel"
        case (.pastel, .spanishSpain): return "Pastel"
        }
    }

    func promptFragment(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.watercolor, .portugueseBrazil):
            return "ilustração infantil em aquarela suave, cores quentes, contornos delicados"
        case (.watercolor, .englishUS):
            return "soft watercolor children's illustration, warm colors, delicate outlines"
        case (.watercolor, .spanishSpain):
            return "ilustración infantil en acuarela suave, colores cálidos, contornos delicados"
        case (.cartoon, .portugueseBrazil):
            return "ilustração cartoon infantil, traços redondos, cores vivas e alegres"
        case (.cartoon, .englishUS):
            return "children's cartoon illustration, round shapes, bright cheerful colors"
        case (.cartoon, .spanishSpain):
            return "ilustración cartoon infantil, trazos redondos, colores vivos y alegres"
        case (.pastel, .portugueseBrazil):
            return "ilustração infantil em tons pastel, textura macia, clima de hora de dormir"
        case (.pastel, .englishUS):
            return "pastel-tone children's illustration, soft texture, bedtime mood"
        case (.pastel, .spanishSpain):
            return "ilustración infantil en tonos pastel, textura suave, clima de hora de dormir"
        }
    }
}

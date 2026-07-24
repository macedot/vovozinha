import Foundation

// MARK: - Story visual memory (actor + anything that appeared)

/// Accumulates visual identities across pages so the hero and every introduced element
/// keep the **same design** while each page still follows its own story text.
struct StoryArtMemory: Sendable, Equatable {
    /// Stable hero visual (same tokens every page).
    var heroLock: String
    /// Story world / setting visual.
    var worldLock: String
    /// Recurring props, friends, places already shown (order = introduction order).
    var lockedElements: [String]
    /// Style bit shared for the whole book.
    var styleBit: String

    static func seed(
        character: CharacterProfile,
        setting: String,
        artStyle: ArtStyle
    ) -> StoryArtMemory {
        StoryArtMemory(
            heroLock: character.artIdentityLock,
            worldLock: ScenePromptBuilder.visualSettingPublic(setting),
            lockedElements: [],
            styleBit: ScenePromptBuilder.shortStylePublic(artStyle)
        )
    }

    /// Merge props discovered on the current page into the lock list.
    mutating func absorb(props: [String], maxElements: Int = 10) {
        for p in props where !p.isEmpty {
            let key = p.lowercased()
            if !lockedElements.contains(where: { $0.lowercased() == key }) {
                lockedElements.append(p)
            }
        }
        if lockedElements.count > maxElements {
            lockedElements = Array(lockedElements.suffix(maxElements))
        }
    }

    /// Line repeated every page so the model never redesigns known subjects.
    var continuityClause: String {
        var parts: [String] = [
            "LOCKED CHARACTER (identical every page): \(heroLock)"
        ]
        if !worldLock.isEmpty {
            parts.append("LOCKED WORLD: \(worldLock)")
        }
        if !lockedElements.isEmpty {
            parts.append(
                "LOCKED STORY ELEMENTS (same design whenever they appear): \(lockedElements.joined(separator: ", "))"
            )
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Art brief

struct SceneArtBrief: Sendable, Equatable {
    var positivePrompt: String
    var negativePrompt: String
    var heroLock: String
    /// This page’s story text (cleaned).
    var sceneDescription: String
    var actionFocus: String
    var lighting: String
    var propHints: [String]
    /// Cumulative locked elements after absorbing this page.
    var continuityLock: String
    /// Narrative section / beat (setup, explore, …, bedtime).
    var sectionTag: String
    /// Section-specific direction baked into the prompt.
    var sectionPrompt: String
    var isEstablishShot: Bool
}

// MARK: - Builder

enum ScenePromptBuilder {
    static let kidsNegativePrompt = """
    lowres, worst quality, low quality, blurry, jpeg artifacts, bad anatomy, bad hands, \
    extra limbs, deformed, ugly, text overlay, watermark, logo, signature, \
    horror, scary, blood, gore, nsfw, weapons, \
    photorealistic, photo, 3d render, western clipart, collage, crowd, \
    different character, character redesign, new face, wrong colors, face morph, \
    redesigned props, changed outfit, inconsistent design, random new character, \
    unrelated scene, random background only
    """
    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    /// Public wrappers so `StoryArtMemory.seed` can share helpers.
    static func shortStylePublic(_ style: ArtStyle) -> String { shortStyle(style) }
    static func visualSettingPublic(_ setting: String) -> String { visualSetting(setting) }

    /// Build a page brief using **section-specific** prompt + **cumulative continuity memory**.
    /// - Returns: brief for this page and updated memory (includes this page’s new elements).
    static func brief(
        pageText: String,
        sceneTag: String,
        character: CharacterProfile,
        setting: String,
        artStyle: ArtStyle,
        language: AppLanguage,
        pageIndex: Int,
        totalPages: Int,
        memory: StoryArtMemory
    ) -> (brief: SceneArtBrief, memory: StoryArtMemory) {
        _ = language
        var mem = memory
        // Keep hero/world/style stable even if caller re-seeds incompletely.
        if mem.heroLock.isEmpty {
            mem.heroLock = character.artIdentityLock
        }
        if mem.worldLock.isEmpty {
            mem.worldLock = visualSetting(setting)
        }
        if mem.styleBit.isEmpty {
            mem.styleBit = shortStyle(artStyle)
        }

        let beat = sceneTag.isEmpty
            ? (pageIndex < StorySceneTags.ordered.count ? StorySceneTags.ordered[pageIndex] : "story")
            : sceneTag
        let cleaned = pageText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let pageScene = excerpt(cleaned, max: 170)
        let action = actionFocus(from: cleaned, beat: beat)
        let lighting = lightingCue(beat: beat, pageIndex: pageIndex, totalPages: totalPages, text: cleaned)
        let pageProps = propHints(from: cleaned + " " + setting)
        let isEstablish = pageIndex == 0
        let section = sectionPrompt(beat: beat, pageIndex: pageIndex, totalPages: totalPages)

        // Absorb this page’s entities so they stay locked on later pages.
        mem.absorb(props: pageProps)

        let continuity = mem.continuityClause
        let recurring = mem.lockedElements.isEmpty
            ? ""
            : "show recurring elements with the same design when relevant: \(mem.lockedElements.joined(separator: ", "))."

        // Custom per-section positive prompt.
        // Order: quality + section → LOCKED cast/world/elements → this page’s story text → action.
        let positive: String
        if isEstablish {
            positive = """
            masterpiece, best quality, \(mem.styleBit), \(section), \
            \(continuity), \
            establish this character clearly in the first frame, \
            illustrate this story page exactly: \(pageScene), \
            the hero is \(action), \(lighting)
            """
        } else {
            positive = """
            masterpiece, best quality, \(mem.styleBit), \(section), \
            \(continuity), \
            do not redesign the hero or any locked story element, \
            \(recurring) \
            illustrate this story page exactly: \(pageScene), \
            the hero is \(action), \(lighting)
            """
        }

        let compact = positive
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let brief = SceneArtBrief(
            positivePrompt: compact,
            negativePrompt: kidsNegativePrompt,
            heroLock: mem.heroLock,
            sceneDescription: pageScene,
            actionFocus: action,
            lighting: lighting,
            propHints: pageProps,
            continuityLock: continuity,
            sectionTag: beat,
            sectionPrompt: section,
            isEstablishShot: isEstablish
        )
        return (brief, mem)
    }

    /// Convenience without memory (single page / planner metadata).
    static func brief(
        pageText: String,
        sceneTag: String,
        character: CharacterProfile,
        setting: String,
        artStyle: ArtStyle,
        language: AppLanguage,
        pageIndex: Int,
        totalPages: Int
    ) -> SceneArtBrief {
        let mem = StoryArtMemory.seed(character: character, setting: setting, artStyle: artStyle)
        return brief(
            pageText: pageText,
            sceneTag: sceneTag,
            character: character,
            setting: setting,
            artStyle: artStyle,
            language: language,
            pageIndex: pageIndex,
            totalPages: totalPages,
            memory: mem
        ).brief
    }

    static func prompt(
        pageText: String,
        sceneTag: String,
        character: CharacterProfile,
        setting: String,
        artStyle: ArtStyle,
        language: AppLanguage,
        pageIndex: Int = 0,
        totalPages: Int = FeatureFlags.fixedPageCount
    ) -> String {
        brief(
            pageText: pageText,
            sceneTag: sceneTag,
            character: character,
            setting: setting,
            artStyle: artStyle,
            language: language,
            pageIndex: pageIndex,
            totalPages: totalPages
        ).positivePrompt
    }

    // MARK: - Section-specific schemas (one prompt style per story beat)

    /// Custom image-direction string for each narrative section.
    static func sectionPrompt(beat: String, pageIndex: Int, totalPages: Int) -> String {
        switch beat {
        case "setup":
            return "SECTION setup: character introduction establishing shot, hero readable and centered, gentle welcome to the world"
        case "explore":
            return "SECTION explore: wide enough to show place + hero, wonder and discovery, soft movement"
        case "inciting":
            return "SECTION inciting: hero notices a small gentle problem, curious focused expression, clear story object"
        case "feel":
            return "SECTION feel: emotional close-medium shot, soft feelings on the hero's face, calm colors"
        case "plan":
            return "SECTION plan: hero thinking of a kind idea, thoughtful pose, hopeful light"
        case "try":
            return "SECTION try: hero carefully trying a first attempt, active pose, clear action"
        case "help":
            return "SECTION help: hero giving or receiving friendly help, second character or helper object if in the page text, warm interaction"
        case "turn":
            return "SECTION turn: things getting better, brighter mood, relieved happy hero"
        case "lesson":
            return "SECTION lesson: kind lesson moment, warm heartfelt composition, soft glow"
        case "bedtime":
            return "SECTION bedtime: cozy good-night closing, calm sleepy mood, gentle night or soft evening light"
        default:
            let ratio = totalPages > 1 ? Double(pageIndex) / Double(totalPages - 1) : 0
            if ratio > 0.85 {
                return "SECTION closing: calm ending moment, soft light"
            }
            return "SECTION story beat: clear single scene focused on the hero and the page action"
        }
    }

    // MARK: - Visual helpers

    private static func shortStyle(_ style: ArtStyle) -> String {
        switch style {
        case .cartoon: return "bright kids anime"
        case .watercolor: return "soft watercolor anime"
        case .pastel: return "soft pastel anime"
        }
    }

    private static func visualSetting(_ setting: String) -> String {
        let t = setting.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        if t.isEmpty { return "" }
        let map: [(String, String)] = [
            ("floresta", "forest"), ("bosque", "forest"), ("forest", "forest"),
            ("mar", "sea"), ("praia", "beach"), ("ocean", "ocean"), ("playa", "beach"),
            ("castelo", "castle"), ("castle", "castle"), ("reino", "kingdom"),
            ("quarto", "bedroom"), ("bedroom", "bedroom"), ("cama", "bedroom"),
            ("fazenda", "farm"), ("farm", "farm"), ("jardim", "garden"), ("garden", "garden"),
            ("cidade", "town"), ("city", "city"),
            ("espaco", "outer space"), ("space", "outer space")
        ]
        var tags: [String] = []
        for (k, v) in map where t.contains(k) {
            if !tags.contains(v) { tags.append(v) }
        }
        if tags.isEmpty { return excerpt(setting, max: 36) }
        return tags.joined(separator: " ")
    }

    private static func visualNouns(from text: String) -> [String] {
        let t = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let pairs: [(String, String)] = [
            ("bird", "small blue bird"), ("passaro", "small blue bird"), ("pajaro", "small blue bird"), ("ave", "small bird"),
            ("nest", "tiny nest"), ("ninho", "tiny nest"), ("nido", "tiny nest"),
            ("tree", "friendly tree"), ("arvore", "friendly tree"), ("arbol", "friendly tree"),
            ("forest", "forest"), ("floresta", "forest"), ("bosque", "forest"),
            ("flower", "bright flower"), ("flor", "bright flower"),
            ("moon", "soft moon"), ("lua", "soft moon"), ("luna", "soft moon"),
            ("star", "gentle stars"), ("estrela", "gentle stars"), ("estrella", "gentle stars"),
            ("sun", "warm sun"), ("sol", "warm sun"),
            ("boat", "small wooden boat"), ("barco", "small wooden boat"),
            ("bed", "cozy bed"), ("cama", "cozy bed"),
            ("fish", "friendly fish"), ("peixe", "friendly fish"), ("pez", "friendly fish"),
            ("door", "simple door"), ("porta", "simple door"), ("puerta", "simple door"),
            ("castle", "soft castle"), ("castelo", "soft castle"), ("castillo", "soft castle"),
            ("path", "soft path"), ("caminho", "soft path"), ("camino", "soft path"),
            ("river", "gentle river"), ("rio", "gentle river"),
            ("sea", "gentle sea"), ("mar", "gentle sea"), ("ocean", "gentle ocean"),
            ("praia", "sandy beach"), ("beach", "sandy beach"),
            ("friend", "small friendly companion"), ("amigo", "small friendly companion"), ("amiga", "small friendly companion"),
            ("bear", "teddy bear"), ("urso", "teddy bear"), ("oso", "teddy bear"),
            ("cat", "soft cat"), ("gato", "soft cat"),
            ("dog", "soft dog"), ("cao", "soft dog"), ("perro", "soft dog"),
            ("rabbit", "soft rabbit"), ("coelho", "soft rabbit"), ("conejo", "soft rabbit"),
            ("butterfly", "butterfly"), ("borboleta", "butterfly"), ("mariposa", "butterfly"),
            ("rain", "soft rain"), ("chuva", "soft rain"), ("lluvia", "soft rain"),
            ("cloud", "fluffy clouds"), ("nuvem", "fluffy clouds"), ("nube", "fluffy clouds"),
            ("home", "cozy home"), ("casa", "cozy home"),
            ("bridge", "small bridge"), ("ponte", "small bridge"), ("puente", "small bridge"),
            ("gift", "small gift"), ("presente", "small gift"), ("regalo", "small gift"),
            ("light", "soft light"), ("luz", "soft light"),
            ("wind", "soft wind"), ("vento", "soft wind"),
            ("leaf", "leaves"), ("folha", "leaves"),
            ("water", "clear water"), ("agua", "clear water")
        ]
        var out: [String] = []
        var seen = Set<String>()
        for (k, v) in pairs where t.contains(k) {
            if seen.insert(v).inserted { out.append(v) }
        }
        return out
    }

    private static func excerpt(_ text: String, max: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > max else { return cleaned }
        let slice = String(cleaned.prefix(max))
        if let r = slice.range(of: #"[.!?]"#, options: .regularExpression) {
            let end = r.upperBound
            if slice.distance(from: slice.startIndex, to: end) >= 48 {
                return String(slice[..<end]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let space = slice.lastIndex(of: " ") {
            return String(slice[..<space]) + "…"
        }
        return slice + "…"
    }

    private static func lightingCue(beat: String, pageIndex: Int, totalPages: Int, text: String) -> String {
        let t = text.lowercased()
        if t.contains("night") || t.contains("noite") || t.contains("noche")
            || t.contains("star") || t.contains("moon") || t.contains("lua") || t.contains("luna")
            || beat == "bedtime" {
            return "night moonlight"
        }
        if t.contains("morning") || t.contains("manhã") || t.contains("manana") || t.contains("sunrise") {
            return "morning sunlight"
        }
        if t.contains("sunset") || t.contains("dusk") || t.contains("entardecer") {
            return "sunset light"
        }
        let ratio = totalPages > 1 ? Double(pageIndex) / Double(totalPages - 1) : 0
        if ratio < 0.35 { return "daytime light" }
        if ratio < 0.7 { return "afternoon light" }
        if beat == "bedtime" || ratio > 0.85 { return "evening bedtime light" }
        return "soft warm light"
    }

    private static func actionFocus(from text: String, beat: String) -> String {
        let t = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let verbs: [(String, String)] = [
            ("help", "helping a friend"), ("ajuda", "helping a friend"), ("ayuda", "helping a friend"),
            ("hug", "hugging"), ("abrac", "hugging"), ("abrazo", "hugging"),
            ("run", "running"), ("corre", "running"),
            ("sleep", "sleeping in bed"), ("dorm", "sleeping in bed"),
            ("fly", "looking upward at something flying"), ("voa", "looking upward at something flying"),
            ("swim", "swimming"), ("nada", "swimming"),
            ("find", "discovering something"), ("encont", "discovering something"),
            ("sing", "singing"), ("canta", "singing"),
            ("smile", "smiling"), ("sorri", "smiling"), ("sonrie", "smiling"),
            ("walk", "walking"), ("camin", "walking"), ("anda", "walking"),
            ("play", "playing"), ("brinc", "playing"), ("juega", "playing"),
            ("look", "looking with wonder"), ("olha", "looking with wonder"), ("mira", "looking with wonder"),
            ("wake", "waking up"), ("acorda", "waking up"), ("despierta", "waking up"),
            ("listen", "listening"), ("ouve", "listening"), ("escuch", "listening"),
            ("give", "giving a gift"), ("entrega", "giving")
        ]
        for (key, focus) in verbs where t.contains(key) {
            return focus
        }
        switch beat {
        case "setup": return "standing in the scene"
        case "explore": return "exploring the place"
        case "inciting": return "noticing a small problem"
        case "feel": return "showing a soft emotion"
        case "plan": return "thinking of an idea"
        case "try": return "trying carefully"
        case "help": return "helping kindly"
        case "turn": return "feeling happy again"
        case "lesson": return "sharing a kind moment"
        case "bedtime": return "getting ready for sleep"
        default: return "in this story moment"
        }
    }

    private static func propHints(from text: String) -> [String] {
        visualNouns(from: text)
    }
}

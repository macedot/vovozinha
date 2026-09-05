import Foundation

/// Structured "story bible": the cast, world, and recurring objects extracted once
/// from the parent's description (+ optional photo tags). It is the global
/// information every later pass must obey — the story weaves it into the prose and
/// every page illustration prompt carries it as a hard requirement.
public struct StoryBible: Equatable, Codable, Sendable {
    /// Main hero identity lock — byte-identical in every page's illustration prompt.
    public var characterLock: String
    /// Other recurring people/creatures; empty when the hero is alone.
    public var supporting: String
    /// Place and time of the whole story.
    public var setting: String
    /// Recurring objects with visual descriptors ("red rose") so later pages
    /// describe the same object with the same words.
    public var props: [String]

    public init(
        characterLock: String,
        supporting: String = "",
        setting: String = "",
        props: [String] = []
    ) {
        self.characterLock = characterLock
        self.supporting = supporting
        self.setting = setting
        self.props = props
    }

    /// Canonical English block injected into the story and illustration templates.
    public var renderedBlock: String {
        var lines: [String] = []
        lines.append("Main character (must look exactly like this on every page): \(characterLock)")
        let support = supporting.trimmingCharacters(in: .whitespaces)
        if !support.isEmpty, support != "(none)" {
            lines.append("Other characters: \(support)")
        }
        let place = setting.trimmingCharacters(in: .whitespaces)
        if !place.isEmpty {
            lines.append("Setting: \(place)")
        }
        if !props.isEmpty {
            lines.append(
                "Recurring objects (always describe them with these exact words): \(props.joined(separator: ", "))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

public enum StoryBibleError: Error, Equatable, Sendable {
    case missingCharacterLock
    case emptyReply
}

/// Whatever a raw reply contained of the four tagged bible lines. Feeds the
/// repair-retry merge; validation stays strict.
public struct StoryBiblePartial: Equatable, Sendable {
    public var characterLock: String
    public var supporting: String
    public var setting: String
    public var props: [String]

    public init(
        characterLock: String = "",
        supporting: String = "",
        setting: String = "",
        props: [String] = []
    ) {
        self.characterLock = characterLock
        self.supporting = supporting
        self.setting = setting
        self.props = props
    }
}

/// Strict tagged-line parser for the bible reply. A missing CHARACTER lock is an
/// error — never fabricate one.
public enum StoryBibleParser {
    public static func parse(_ raw: String) throws -> StoryBible {
        try validate(parsePartial(raw))
    }

    public static func validate(_ partial: StoryBiblePartial) throws -> StoryBible {
        guard !partial.characterLock.isEmpty else { throw StoryBibleError.missingCharacterLock }
        return StoryBible(
            characterLock: partial.characterLock,
            supporting: partial.supporting,
            setting: partial.setting,
            props: partial.props
        )
    }

    /// Scan a raw reply for the CHARACTER/ALSO/SETTING/PROPS lines — without failing.
    public static func parsePartial(_ raw: String) -> StoryBiblePartial {
        let text = stripCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return StoryBiblePartial() }

        var partial = StoryBiblePartial()
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = normalizeLine(String(line))
            guard !trimmed.isEmpty else { continue }
            let upper = trimmed.uppercased()
            if let value = taggedValue("CHARACTER:", in: trimmed, upper: upper),
               partial.characterLock.isEmpty {
                partial.characterLock = value
            } else if let value = taggedValue("ALSO:", in: trimmed, upper: upper),
                      partial.supporting.isEmpty {
                partial.supporting = value == "(none)" ? "" : value
            } else if let value = taggedValue("SETTING:", in: trimmed, upper: upper),
                      partial.setting.isEmpty {
                partial.setting = value
            } else if let value = taggedValue("PROPS:", in: trimmed, upper: upper),
                      partial.props.isEmpty {
                partial.props = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                .filter { !$0.isEmpty && $0 != "(none)" }
            }
        }
        return partial
    }

    private static func taggedValue(_ tag: String, in line: String, upper: String) -> String? {
        guard upper.hasPrefix(tag) else { return nil }
        return String(line.dropFirst(tag.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Drop markdown fences the model sometimes wraps around the reply.
    static func stripCodeFences(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(pattern: #"```[a-zA-Z0-9]*\s*"#, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }

    /// Strip bullets / bold so `**CHARACTER:** …` still parses.
    static func normalizeLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        while s.hasPrefix("*") || s.hasPrefix("-") || s.hasPrefix("#") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return s
    }
}

public protocol StoryBibleGenerating: Sendable {
    /// Fuses the parent's description with optional photo element tags into the
    /// story bible. `photoTags` may be nil (no photo) — the cast is then imagined
    /// from the description alone.
    func generate(description: String, photoTags: String?) async throws -> StoryBible
}

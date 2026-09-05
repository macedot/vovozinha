import Foundation

public struct IllustrationPlan: Equatable, Sendable {
    public var characterDescriptor: String
    public var prompts: [String]

    public init(characterDescriptor: String, prompts: [String]) {
        self.characterDescriptor = characterDescriptor
        self.prompts = prompts
    }
}

/// Whatever a raw reply contained: the CHARACTER/CAST line plus any numbered
/// lines found. Feeds the repair-retry merge; validation stays strict.
public struct IllustrationPartial: Equatable, Sendable {
    public var descriptor: String
    public var lines: [Int: String]

    public init(descriptor: String = "", lines: [Int: String] = [:]) {
        self.descriptor = descriptor
        self.lines = lines
    }
}

public enum IllustrationPromptError: Error, Equatable, Sendable {
    case missingLines([Int])
    case missingCharacterDescriptor
    case emptyReply
}

/// Strict numbered-line parser. Missing lines are errors — never fabricate.
public enum IllustrationPromptParser {
    public static let requiredCount = 10

    public static func parse(_ raw: String) throws -> IllustrationPlan {
        try validate(parsePartial(raw))
    }

    /// Strict validation of scanned content: descriptor required, all 10 lines required.
    public static func validate(_ partial: IllustrationPartial) throws -> IllustrationPlan {
        guard !partial.descriptor.isEmpty else { throw IllustrationPromptError.missingCharacterDescriptor }
        let missing = (1...requiredCount).filter { (partial.lines[$0] ?? "").isEmpty }
        if !missing.isEmpty { throw IllustrationPromptError.missingLines(missing) }
        return IllustrationPlan(
            characterDescriptor: partial.descriptor,
            prompts: (1...requiredCount).map { partial.lines[$0]! }
        )
    }

    /// Scan a raw reply for the CHARACTER/CAST line and numbered lines — without
    /// failing. Used to build targeted repair prompts and to merge repairs.
    public static func parsePartial(_ raw: String) -> IllustrationPartial {
        let text = stripCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return IllustrationPartial() }

        var partial = IllustrationPartial()
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = normalizeLine(String(line))
            if trimmed.isEmpty { continue }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("CHARACTER:") || upper.hasPrefix("CAST:") {
                let prefix = upper.hasPrefix("CAST:") ? "CAST:" : "CHARACTER:"
                let found = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if partial.descriptor.isEmpty { partial.descriptor = found }
                continue
            }
            if let (index, body) = numberedLine(trimmed), (partial.lines[index] ?? "").isEmpty {
                partial.lines[index] = body
            }
        }
        return partial
    }

    private static func numberedLine(_ line: String) -> (Int, String)? {
        let pattern = #"^\s*(\d{1,2})[\.\)\:\-]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 3,
              let iRange = Range(match.range(at: 1), in: line),
              let bRange = Range(match.range(at: 2), in: line),
              let index = Int(line[iRange]),
              (1...requiredCount).contains(index)
        else { return nil }
        return (index, String(line[bRange]).trimmingCharacters(in: .whitespaces))
    }

    /// Drop markdown fences Qwen sometimes wraps around the list.
    static func stripCodeFences(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(pattern: #"```[a-zA-Z0-9]*\s*"#, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }

    /// Strip bullets / bold so `**1.** scene` and `- CHARACTER: …` still parse.
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

public protocol IllustrationPromptGenerating: Sendable {
    func generate(draftTitle: String, paragraphs: [String], caption: String?) async throws -> IllustrationPlan
}

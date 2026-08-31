import Foundation

public struct IllustrationPlan: Equatable, Sendable {
    public var characterDescriptor: String
    public var prompts: [String]

    public init(characterDescriptor: String, prompts: [String]) {
        self.characterDescriptor = characterDescriptor
        self.prompts = prompts
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
        let text = stripCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IllustrationPromptError.emptyReply }

        var descriptor = ""
        var byIndex: [Int: String] = [:]

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = normalizeLine(String(line))
            if trimmed.isEmpty { continue }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("CHARACTER:") || upper.hasPrefix("CAST:") {
                let prefix = upper.hasPrefix("CAST:") ? "CAST:" : "CHARACTER:"
                descriptor = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            if let (index, body) = numberedLine(trimmed) {
                byIndex[index] = body
            }
        }

        guard !descriptor.isEmpty else { throw IllustrationPromptError.missingCharacterDescriptor }

        var missing: [Int] = []
        var prompts: [String] = []
        for i in 1...requiredCount {
            if let p = byIndex[i], !p.isEmpty {
                prompts.append(p)
            } else {
                missing.append(i)
            }
        }
        if !missing.isEmpty { throw IllustrationPromptError.missingLines(missing) }
        return IllustrationPlan(characterDescriptor: descriptor, prompts: prompts)
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

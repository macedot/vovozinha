import Foundation

/// Base story idea typed by the parent. Length is measured in **words**.
public struct StorySeedPrompt: Equatable, Sendable {
    public static let minWords = 10
    public static let maxWords = 20

    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var words: [String] {
        trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var wordCount: Int { words.count }

    public var isValid: Bool {
        let n = wordCount
        return n >= Self.minWords && n <= Self.maxWords
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case tooShort(current: Int)
        case tooLong(current: Int)
    }

    public func validate() throws {
        let n = wordCount
        if n < Self.minWords { throw ValidationError.tooShort(current: n) }
        if n > Self.maxWords { throw ValidationError.tooLong(current: n) }
    }
}

/// Result of turning a seed prompt into a story draft (text only for this phase).
public struct StoryDraft: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var seedPrompt: String
    public var paragraphs: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        seedPrompt: String,
        paragraphs: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.seedPrompt = seedPrompt
        self.paragraphs = paragraphs
        self.createdAt = createdAt
    }

    public var fullText: String {
        paragraphs.joined(separator: "\n\n")
    }
}

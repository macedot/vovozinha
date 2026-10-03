import Foundation

public struct StoryPage: Equatable, Sendable, Identifiable, Codable {
    public var index: Int
    public var text: String

    public var id: Int { index }

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }
}

public struct Storybook: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var language: String
    /// The parent's original description, kept so a saved story can be checked
    /// against what was actually generated.
    public var seedPrompt: String
    public var phase: PipelinePhase
    public var pages: [StoryPage]
    public var createdAt: Date

    public init(
        id: UUID,
        title: String,
        summary: String,
        language: String,
        seedPrompt: String,
        phase: PipelinePhase,
        pages: [StoryPage],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.language = language
        self.seedPrompt = seedPrompt
        self.phase = phase
        self.pages = pages
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, language, seedPrompt, phase, pages, createdAt
    }

    /// Older `history.json` files omitted `seedPrompt`. Those books still open;
    /// the description is empty until a new story stores one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        seedPrompt = try container.decodeIfPresent(String.self, forKey: .seedPrompt) ?? ""
        phase = try container.decodeIfPresent(PipelinePhase.self, forKey: .phase) ?? .finished
        pages = try container.decodeIfPresent([StoryPage].self, forKey: .pages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(language, forKey: .language)
        try container.encode(seedPrompt, forKey: .seedPrompt)
        try container.encode(phase, forKey: .phase)
        try container.encode(pages, forKey: .pages)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public enum PipelinePhase: String, Equatable, Sendable, Codable {
    case story
    case finished
    case failed
}

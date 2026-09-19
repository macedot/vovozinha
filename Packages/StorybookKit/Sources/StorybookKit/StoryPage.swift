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
}

public enum PipelinePhase: String, Equatable, Sendable, Codable {
    case story
    case finished
    case failed
}

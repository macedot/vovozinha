import Foundation

public struct StoryPage: Equatable, Sendable, Identifiable {
    public var index: Int
    public var text: String
    public var illustrationPrompt: String
    /// Relative filename under the story directory, e.g. `page-1.png`.
    public var imageFileName: String?

    public var id: Int { index }

    public init(
        index: Int,
        text: String,
        illustrationPrompt: String,
        imageFileName: String? = nil
    ) {
        self.index = index
        self.text = text
        self.illustrationPrompt = illustrationPrompt
        self.imageFileName = imageFileName
    }
}

public struct Storybook: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var language: String
    public var seedPrompt: String
    public var characterDescriptor: String
    public var baseSeed: UInt32
    public var phase: PipelinePhase
    public var pages: [StoryPage]
    public var createdAt: Date

    public init(
        id: UUID,
        title: String,
        summary: String,
        language: String,
        seedPrompt: String,
        characterDescriptor: String,
        baseSeed: UInt32,
        phase: PipelinePhase,
        pages: [StoryPage],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.language = language
        self.seedPrompt = seedPrompt
        self.characterDescriptor = characterDescriptor
        self.baseSeed = baseSeed
        self.phase = phase
        self.pages = pages
        self.createdAt = createdAt
    }
}

public enum PipelinePhase: String, Equatable, Sendable {
    case caption
    case story
    case illustrationPrompts
    case reference
    case pages
    case finished
    case failed
}

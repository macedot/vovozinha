import Foundation
import StoryPromptKit

public struct StoryPage: Equatable, Sendable, Identifiable, Codable {
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

public struct Storybook: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var language: String
    public var seedPrompt: String
    public var characterDescriptor: String
    /// Extracted cast/world/props the story and every illustration must obey.
    /// nil for books made before the bible pass (or when extraction failed).
    public var bible: StoryBible?
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
        bible: StoryBible? = nil,
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
        self.bible = bible
        self.baseSeed = baseSeed
        self.phase = phase
        self.pages = pages
        self.createdAt = createdAt
    }
}

public enum PipelinePhase: String, Equatable, Sendable, Codable {
    case caption
    case bible
    case story
    case illustrationPrompts
    case reference
    case pages
    case finished
    case failed
}

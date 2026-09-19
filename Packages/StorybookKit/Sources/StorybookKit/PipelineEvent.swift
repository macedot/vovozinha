import Foundation

public enum PipelineEvent: Equatable, Sendable {
    case phaseChanged(PipelinePhase)
    case pageTextsReady(pages: [StoryPage], title: String, summary: String)
    case failed(message: String)
    case finished
}

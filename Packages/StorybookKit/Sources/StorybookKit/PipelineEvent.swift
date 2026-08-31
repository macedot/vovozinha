import Foundation

public enum PipelineEvent: Equatable, Sendable {
    case phaseChanged(PipelinePhase)
    case pageTextsReady(pages: [StoryPage], title: String, summary: String)
    case illustrationReady(index: Int, fileName: String)
    case progress(step: Int, of: Int)
    case failed(message: String)
    case finished
}

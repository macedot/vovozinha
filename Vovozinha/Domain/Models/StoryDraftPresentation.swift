import Foundation

/// Wrapper so generation can be presented via `fullScreenCover(item:)` (never empty content).
struct StoryDraftPresentation: Identifiable {
    let id: UUID
    let draft: StoryDraftInput

    init(draft: StoryDraftInput, id: UUID = UUID()) {
        self.id = id
        self.draft = draft
    }
}

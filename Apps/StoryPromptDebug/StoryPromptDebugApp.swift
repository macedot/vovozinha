import SwiftUI
import StoryPromptKit
import VovoUI

/// DEBUG harness: runs `StoryPromptKit` alone with the shared Vovo visual template.
@main
struct StoryPromptDebugApp: App {
    @State private var languageStore = LanguageStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StoryPromptFeatureView()
                    .navigationTitle("StoryPrompt · Debug")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbarBackground(VovoTheme.deepNight.opacity(0.9), for: .navigationBar)
            }
            .environment(languageStore)
            .preferredColorScheme(.dark)
        }
    }
}

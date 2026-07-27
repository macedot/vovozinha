import SwiftUI
import StoryPromptKit
import VovoUI

/// DEBUG harness: runs `StoryPromptKit` alone.
/// Model download gate lives inside `StoryPromptFeatureView` (same as the host app).
@main
struct StoryPromptDebugApp: App {
    @State private var languageStore = LanguageStore()
    @State private var modelStore = BonsaiModelStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StoryPromptFeatureView(
                    generator: DeviceStoryGenerator(modelStore: modelStore),
                    modelStore: modelStore
                )
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

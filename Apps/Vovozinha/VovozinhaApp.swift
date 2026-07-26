import SwiftUI
import StoryPromptKit
import VovoUI

@main
struct VovozinhaApp: App {
    @State private var languageStore = LanguageStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(languageStore)
                .preferredColorScheme(.dark)
        }
    }
}

/// Host app: composes feature libraries into the product experience.
private struct RootView: View {
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        NavigationStack {
            StoryPromptFeatureView()
                .navigationTitle("Vovozinha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(VovoTheme.deepNight.opacity(0.9), for: .navigationBar)
        }
    }
}

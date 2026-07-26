import SwiftUI
import StoryPromptKit
import VovoUI

@main
struct VovozinhaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Host app: composes feature libraries into the product experience.
private struct RootView: View {
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

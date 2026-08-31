import SwiftUI
import StorybookKit
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

private struct RootView: View {
    var body: some View {
        NavigationStack {
            StorybookFeatureView()
                .navigationTitle("Vovozinha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(VovoTheme.deepNight.opacity(0.9), for: .navigationBar)
        }
    }
}

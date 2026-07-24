import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case library
    case create
    case settings
}

struct ContentView: View {
    @Environment(LanguageStore.self) private var languageStore
    @State private var selectedTab: AppTab = .library

    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        VStack(spacing: 0) {
            LanguageBar()

            TabView(selection: $selectedTab) {
                LibraryView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(L10n.t(.tabLibrary, lang), systemImage: "books.vertical.fill")
                    }
                    .tag(AppTab.library)

                QuickCreateStoryView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(L10n.t(.tabCreate, lang), systemImage: "sparkles")
                    }
                    .tag(AppTab.create)

                SettingsView()
                    .tabItem {
                        Label(L10n.t(.tabSettings, lang), systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)
            }
            .tint(VovoTheme.amber)
        }
        .background(VovoTheme.deepNight.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
        .environment(LanguageStore())
        .modelContainer(for: [Story.self, StoryPage.self], inMemory: true)
}

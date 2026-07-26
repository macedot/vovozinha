import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case create
    case library
    case settings

    /// Cold-start tab: Create when the library is empty, otherwise Library.
    static func launchTab(hasStories: Bool) -> AppTab {
        hasStories ? .library : .create
    }
}

struct ContentView: View {
    @Environment(LanguageStore.self) private var languageStore
    @Query(sort: \Story.createdAt, order: .reverse) private var stories: [Story]
    @State private var selectedTab: AppTab = .create
    @State private var didApplyLaunchTab = false

    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        VStack(spacing: 0) {
            LanguageBar()

            TabView(selection: $selectedTab) {
                // Leftmost: create story
                QuickCreateStoryView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(L10n.t(.tabCreate, lang), systemImage: "sparkles")
                    }
                    .tag(AppTab.create)

                LibraryView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(L10n.t(.tabLibrary, lang), systemImage: "books.vertical.fill")
                    }
                    .tag(AppTab.library)

                SettingsView()
                    .tabItem {
                        Label(L10n.t(.tabSettings, lang), systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)
            }
            .tint(VovoTheme.amber)
        }
        .background(VovoTheme.deepNight.ignoresSafeArea())
        .onAppear {
            applyLaunchTabIfNeeded()
        }
        .onChange(of: stories.count) { _, _ in
            // First paint can race an empty Query; apply once when data is known.
            applyLaunchTabIfNeeded()
        }
    }

    private func applyLaunchTabIfNeeded() {
        guard !didApplyLaunchTab else { return }
        didApplyLaunchTab = true
        selectedTab = AppTab.launchTab(hasStories: !stories.isEmpty)
    }
}

#Preview {
    ContentView()
        .environment(LanguageStore())
        .modelContainer(for: [Story.self, StoryPage.self], inMemory: true)
}

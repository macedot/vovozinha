import SwiftUI
import SwiftData

@main
struct VovozinhaApp: App {
    @AppStorage(AppSettings.ageGateAcceptedKey) private var ageGateAccepted = false
    @State private var languageStore = LanguageStore()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Story.self, StoryPage.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData open failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if ageGateAccepted {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(languageStore)
            .preferredColorScheme(.dark)
            // Force view refresh when language preference changes.
            .id(languageStore.preferenceRaw + "-" + languageStore.language.rawValue)
        }
        .modelContainer(sharedModelContainer)
    }
}

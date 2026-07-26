import SwiftUI
import SwiftData

struct LibraryView: View {
    @Binding var selectedTab: AppTab
    @Environment(LanguageStore.self) private var languageStore
    @Query(sort: \Story.createdAt, order: .reverse) private var stories: [Story]
    @State private var path = NavigationPath()

    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                VovoTheme.backgroundGradient.ignoresSafeArea()

                if stories.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(stories) { story in
                                NavigationLink(value: story.id) {
                                    StoryCard(story: story)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle(L10n.t(.libraryTitle, lang))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let story = stories.first(where: { $0.id == id }) {
                    ReaderView(story: story)
                } else {
                    Text(L10n.t(.readerMissing, lang))
                        .foregroundStyle(VovoTheme.cream)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(VovoTheme.amber.opacity(0.85))
            Text(L10n.t(.libraryEmptyTitle, lang))
                .font(.title3.bold())
                .foregroundStyle(VovoTheme.cream)
            Text(L10n.t(.libraryEmptyBody, lang))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(VovoTheme.cream.opacity(0.7))
                .padding(.horizontal, 32)

            Button(L10n.t(.libraryCreateCTA, lang)) {
                selectedTab = .create
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }
}

struct StoryCard: View {
    let story: Story

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [VovoTheme.indigo, VovoTheme.deepNight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let image = story.coverUIImage() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 8) {
                        Text(String(story.title.prefix(1)).uppercased())
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(VovoTheme.amber)
                        Image(systemName: "text.book.closed.fill")
                            .foregroundStyle(VovoTheme.cream.opacity(0.7))
                    }
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(story.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VovoTheme.cream)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(story.lesson)
                .font(.caption)
                .foregroundStyle(VovoTheme.amber.opacity(0.9))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(VovoTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(VovoTheme.cardStroke)
                )
        )
    }
}

#Preview {
    LibraryView(selectedTab: .constant(.library))
        .environment(LanguageStore())
        .modelContainer(for: [Story.self, StoryPage.self], inMemory: true)
}

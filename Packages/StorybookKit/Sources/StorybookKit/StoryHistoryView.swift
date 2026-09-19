import Foundation
import SwiftUI
import VovoUI

public struct StoryHistoryView: View {
    @Environment(LanguageStore.self) private var languageStore
    @State private var stories: [Storybook] = []
    @State private var errorMessage: String?

    private let store: StoryHistoryStore

    public init(store: StoryHistoryStore = StoryHistoryStore()) {
        self.store = store
    }

    private var lang: AppLanguage { languageStore.language }

    public var body: some View {
        VovoScreen(
            title: VovoL10n.t(.storyHistoryTitle, lang),
            subtitle: VovoL10n.t(.storyHistorySubtitle, lang)
        ) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(VovoTheme.softPink)
            }

            if stories.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(stories) { story in
                        NavigationLink(value: story.id) {
                            historyCard(story)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(story)
                            } label: {
                                Label(
                                    VovoL10n.t(.storyHistoryDelete, lang),
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
        }
        .task { reload() }
        .refreshable { reload() }
        .navigationDestination(for: UUID.self) { id in
            if let story = stories.first(where: { $0.id == id }) {
                StoryHistoryReaderView(story: story)
            } else {
                Text(VovoL10n.t(.storyHistoryMissing, lang))
                    .foregroundStyle(VovoTheme.cream)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42))
                .foregroundStyle(VovoTheme.amber)
            Text(VovoL10n.t(.storyHistoryEmptyTitle, lang))
                .font(.title3.bold())
                .foregroundStyle(VovoTheme.cream)
            Text(VovoL10n.t(.storyHistoryEmptyBody, lang))
                .multilineTextAlignment(.center)
                .foregroundStyle(VovoTheme.cream.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func historyCard(_ story: Storybook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(VovoTheme.amber)
                Text(story.title.isEmpty ? VovoL10n.t(.storyScene, lang) : story.title)
                    .font(.headline)
                    .foregroundStyle(VovoTheme.cream)
                    .lineLimit(2)
                Spacer()
                Text(story.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(VovoTheme.cream.opacity(0.62))
            }

            Text(VovoL10n.historyPageCount(story.pages.count, lang: lang))
                .font(.caption)
                .foregroundStyle(VovoTheme.amber.opacity(0.9))

            if !story.summary.isEmpty {
                Text(story.summary)
                    .font(.subheadline)
                    .foregroundStyle(VovoTheme.cream.opacity(0.72))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VovoTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VovoTheme.cardStroke)
                )
        )
    }

    private func reload() {
        do {
            stories = try store.load()
            errorMessage = nil
        } catch {
            errorMessage = VovoL10n.t(.storyHistoryLoadFailed, lang)
        }
    }

    private func delete(_ story: Storybook) {
        do {
            try store.delete(story)
            stories.removeAll { $0.id == story.id }
        } catch {
            errorMessage = VovoL10n.t(.storyHistoryDeleteFailed, lang)
        }
    }
}

public struct StoryHistoryReaderView: View {
    @Environment(LanguageStore.self) private var languageStore

    private let story: Storybook

    public init(story: Storybook) {
        self.story = story
    }

    private var lang: AppLanguage { languageStore.language }

    public var body: some View {
        TabView {
            ForEach(story.pages) { page in
                VovoScreen(
                    title: story.title.isEmpty ? VovoL10n.t(.storyScene, lang) : story.title,
                    subtitle: story.summary,
                    scrolls: true
                ) {
                    Text(page.text)
                        .font(.body)
                        .foregroundStyle(VovoTheme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .always))
        #endif
        .navigationTitle(story.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

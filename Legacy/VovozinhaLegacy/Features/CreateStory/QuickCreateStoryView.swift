import SwiftUI
import SwiftData

/// Quick create: **description field + generate only**. Everything else is under Customize.
struct QuickCreateStoryView: View {
    @Binding var selectedTab: AppTab

    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var languageStore
    @State private var actorDescription = ""
    @State private var presentedDraft: StoryDraftPresentation?

    private var lang: AppLanguage { languageStore.language }

    private func exitGenerationFlowToMain() {
        presentedDraft = nil
        selectedTab = .library
    }

    private var hasActor: Bool {
        !actorDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canGenerate: Bool { hasActor }

    var body: some View {
        NavigationStack {
            ZStack {
                VovoTheme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 20) {
                    TextField(
                        L10n.t(.createDescriptionPlaceholder, lang),
                        text: $actorDescription,
                        axis: .vertical
                    )
                    .lineLimit(6...12)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(VovoTheme.cardFill)
                    )
                    .foregroundStyle(VovoTheme.cream)
                    .tint(VovoTheme.amber)

                    if !hasActor {
                        Text(L10n.t(.createNeedActor, lang))
                            .font(.caption)
                            .foregroundStyle(VovoTheme.softPink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(L10n.t(.createGenerate, lang)) {
                        let draft = StoryDraftInput.randomized(
                            actorDescription: actorDescription,
                            photoData: nil,
                            language: lang
                        )
                        presentedDraft = StoryDraftPresentation(draft: draft)
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canGenerate))
                    .disabled(!canGenerate)

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
            .navigationTitle(L10n.t(.createTitle, lang))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CustomCreateStoryView(selectedTab: $selectedTab)
                    } label: {
                        Text(L10n.t(.createCustomize, lang))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(VovoTheme.amber)
                    }
                }
            }
            .fullScreenCover(item: $presentedDraft) { presentation in
                GenerationView(
                    draft: presentation.draft,
                    onExitToMain: exitGenerationFlowToMain
                )
                .environment(\.modelContext, modelContext)
                .environment(languageStore)
            }
        }
    }
}

#Preview {
    QuickCreateStoryView(selectedTab: .constant(.create))
        .environment(LanguageStore())
        .modelContainer(for: [Story.self, StoryPage.self], inMemory: true)
}

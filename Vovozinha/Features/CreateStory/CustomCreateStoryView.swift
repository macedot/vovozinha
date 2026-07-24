import SwiftUI
import PhotosUI
import SwiftData

struct CustomCreateStoryView: View {
    @Binding var selectedTab: AppTab

    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var languageStore
    @State private var actorName = ""
    @State private var actorDescription = ""
    @State private var storyIdea = ""
    @State private var setting = ""
    @State private var customSetting = ""
    @State private var lesson = ""
    @State private var customLesson = ""
    @State private var ageBand: AgeBand = .threeToFive
    @State private var artStyle: ArtStyle = .watercolor
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var presentedDraft: StoryDraftPresentation?
    @State private var didSeedSuggestions = false

    private var lang: AppLanguage { languageStore.language }

    private func exitGenerationFlowToMain() {
        presentedDraft = nil
        selectedTab = .library
    }

    private var liveDraft: StoryDraftInput {
        StoryDraftInput(
            actorName: actorName,
            actorDescription: actorDescription,
            photoData: photoData,
            setting: resolvedSetting,
            lesson: resolvedLesson,
            ageBand: ageBand,
            artStyle: artStyle,
            storyIdea: storyIdea,
            pageCount: FeatureFlags.fixedPageCount,
            language: lang
        )
    }

    private var resolvedSetting: String {
        customSetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? setting : customSetting
    }

    private var resolvedLesson: String {
        customLesson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lesson : customLesson
    }

    private var llmReady: Bool { DeviceProfile.current.canGenerateStories }

    private var canGenerate: Bool { liveDraft.isValid && llmReady }

    var body: some View {
        ZStack {
            VovoTheme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    capabilityBanners
                    actorSection

                    fieldBlock(title: L10n.t(.customAge, lang)) {
                        HStack(spacing: 10) {
                            ForEach(AgeBand.allCases) { band in
                                ChipButton(title: band.title(lang), isSelected: ageBand == band) {
                                    ageBand = band
                                }
                            }
                        }
                        Text(ageBand.subtitle(lang))
                            .font(.caption)
                            .foregroundStyle(VovoTheme.cream.opacity(0.55))
                    }

                    fieldBlock(title: L10n.t(.customWorld, lang)) {
                        chipWrap(StoryDraftInput.settingSuggestions(for: lang), selection: $setting)
                        TextField(L10n.t(.customWorldOther, lang), text: $customSetting)
                            .textFieldStyle(VovoFieldStyle())
                    }

                    fieldBlock(title: L10n.t(.customLesson, lang)) {
                        chipWrap(StoryDraftInput.lessonSuggestions(for: lang), selection: $lesson)
                        TextField(L10n.t(.customLessonOther, lang), text: $customLesson)
                            .textFieldStyle(VovoFieldStyle())
                    }

                    fieldBlock(title: L10n.t(.customIdea, lang)) {
                        Text(liveDraft.parametersSummaryLine())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VovoTheme.amber.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)

                        TextField(
                            L10n.t(.customIdeaPlaceholder, lang),
                            text: $storyIdea,
                            axis: .vertical
                        )
                        .lineLimit(3...5)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(VovoTheme.cardFill)
                        )
                        .foregroundStyle(VovoTheme.cream)
                        .tint(VovoTheme.amber)
                    }

                    fieldBlock(title: L10n.t(.customStyle, lang)) {
                        HStack(spacing: 10) {
                            ForEach(ArtStyle.allCases) { style in
                                ChipButton(title: style.title(lang), isSelected: artStyle == style) {
                                    artStyle = style
                                }
                            }
                        }
                    }

                    fieldBlock(title: L10n.t(.customPages, lang)) {
                        Text("\(FeatureFlags.fixedPageCount)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(VovoTheme.cream)
                        Text(L10n.t(.customPagesBody, lang))
                            .font(.caption)
                            .foregroundStyle(VovoTheme.cream.opacity(0.55))
                    }

                    if liveDraft.isValid && llmReady {
                        Text("\(L10n.t(.customActorReady, lang)): \(liveDraft.resolvedActorName())")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(VovoTheme.mint)
                    } else if !liveDraft.isValid {
                        Text(L10n.t(.customNeedActor, lang))
                            .font(.subheadline)
                            .foregroundStyle(VovoTheme.softPink)
                    } else if !llmReady {
                        Text(StoryPlanningError.llmUnavailable.localizedDescription(for: lang))
                            .font(.subheadline)
                            .foregroundStyle(VovoTheme.softPink)
                    }

                    Button(L10n.t(.customGenerate, lang)) {
                        presentedDraft = StoryDraftPresentation(draft: liveDraft)
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canGenerate))
                    .disabled(!canGenerate)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
                .padding(20)
            }
        }
        .navigationTitle(L10n.t(.customTitle, lang))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { seedSuggestionsIfNeeded() }
        .onChange(of: languageStore.language) { _, _ in
            // Reset chips when language changes so labels match.
            setting = StoryDraftInput.settingSuggestions(for: lang).first ?? ""
            lesson = StoryDraftInput.lessonSuggestions(for: lang).first ?? ""
            customSetting = ""
            customLesson = ""
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
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

    private func seedSuggestionsIfNeeded() {
        guard !didSeedSuggestions else { return }
        didSeedSuggestions = true
        setting = StoryDraftInput.settingSuggestions(for: lang).first ?? ""
        lesson = StoryDraftInput.lessonSuggestions(for: lang).first ?? ""
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.customHeader, lang))
                .font(.title3.bold())
                .foregroundStyle(VovoTheme.cream)
            Text(L10n.t(.customHeaderBody, lang))
                .font(.subheadline)
                .foregroundStyle(VovoTheme.cream.opacity(0.7))
        }
    }

    @ViewBuilder
    private var capabilityBanners: some View {
        let profile = DeviceProfile.current
        let graphics = profile.availability(for: .graphicsPipeline, lang: lang)
        let fm = profile.availability(for: .foundationModelsStory, lang: lang)

        if !graphics.isUsable {
            capabilityBanner(icon: "paintbrush.pointed", text: graphics.userMessage(lang))
        }
        if !fm.isUsable {
            capabilityBanner(
                icon: "apple.logo",
                text: L10n.t(.featureBannerFoundationModelsOff, lang)
            )
        }
        if !profile.canGenerateStories {
            capabilityBanner(
                icon: "exclamationmark.triangle.fill",
                text: StoryPlanningError.llmUnavailable.localizedDescription(for: lang)
            )
        }
    }

    private func capabilityBanner(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(VovoTheme.amber)
            Text(text)
                .font(.caption)
                .foregroundStyle(VovoTheme.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VovoTheme.cardFill)
        )
    }

    private var actorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t(.customActor, lang))
                .font(.headline)
                .foregroundStyle(VovoTheme.cream)

            HStack(spacing: 16) {
                photoThumb
                photoControls
            }

            TextField(L10n.t(.customNamePlaceholder, lang), text: $actorName)
                .textFieldStyle(VovoFieldStyle())

            TextField(
                L10n.t(.customDescriptionPlaceholder, lang),
                text: $actorDescription,
                axis: .vertical
            )
            .lineLimit(3...5)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VovoTheme.cardFill)
            )
            .foregroundStyle(VovoTheme.cream)
            .tint(VovoTheme.amber)
        }
    }

    private var photoThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(VovoTheme.cardFill)
                .frame(width: 112, height: 112)
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Image(systemName: "camera.fill")
                    .font(.title)
                    .foregroundStyle(VovoTheme.amber)
            }
        }
    }

    private var photoControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    photoData == nil ? L10n.t(.customChoosePhoto, lang) : L10n.t(.customSwapPhoto, lang),
                    systemImage: "photo"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VovoTheme.deepNight)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(VovoTheme.amber))
            }
            if photoData != nil {
                Button(L10n.t(.customRemovePhoto, lang)) {
                    photoItem = nil
                    photoData = nil
                    photoImage = nil
                }
                .font(.caption)
                .foregroundStyle(VovoTheme.softPink)
            }
            Text(L10n.t(.customPhotoOnDevice, lang))
                .font(.caption2)
                .foregroundStyle(VovoTheme.cream.opacity(0.5))
        }
    }

    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(VovoTheme.cream)
            content()
        }
    }

    private func chipWrap(_ items: [String], selection: Binding<String>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                ChipButton(title: item, isSelected: selection.wrappedValue == item) {
                    selection.wrappedValue = item
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            photoData = data
            photoImage = UIImage(data: data)
        }
    }
}

#Preview {
    NavigationStack {
        CustomCreateStoryView(selectedTab: .constant(.create))
    }
    .environment(LanguageStore())
    .modelContainer(for: [Story.self, StoryPage.self], inMemory: true)
}

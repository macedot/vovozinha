import SwiftUI
import PhotosUI
import SwiftData

struct QuickCreateStoryView: View {
    @Binding var selectedTab: AppTab

    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var languageStore
    @State private var actorDescription = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var presentedDraft: StoryDraftPresentation?

    private var lang: AppLanguage { languageStore.language }

    /// Leave generate/reader covers and show the main library tab.
    private func exitGenerationFlowToMain() {
        presentedDraft = nil
        selectedTab = .library
    }

    private var hasActor: Bool {
        !actorDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil
    }

    private var llmReady: Bool { DeviceProfile.current.canGenerateStories }

    private var canGenerate: Bool { hasActor && llmReady }

    var body: some View {
        NavigationStack {
            ZStack {
                VovoTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        capabilityBanners
                        photoBlock
                        descriptionBlock

                        if !hasActor {
                            Text(L10n.t(.createNeedActor, lang))
                                .font(.subheadline)
                                .foregroundStyle(VovoTheme.softPink)
                        } else if !llmReady {
                            Text(StoryPlanningError.llmUnavailable.localizedDescription(for: lang))
                                .font(.subheadline)
                                .foregroundStyle(VovoTheme.softPink)
                        }

                        Button(L10n.t(.createGenerate, lang)) {
                            let draft = StoryDraftInput.randomized(
                                actorDescription: actorDescription,
                                photoData: photoData,
                                language: lang
                            )
                            presentedDraft = StoryDraftPresentation(draft: draft)
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: canGenerate))
                        .disabled(!canGenerate)

                        NavigationLink {
                            CustomCreateStoryView(selectedTab: $selectedTab)
                        } label: {
                            Text(L10n.t(.createCustomize, lang))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Text(L10n.t(.createRandomHint, lang))
                            .font(.caption)
                            .foregroundStyle(VovoTheme.cream.opacity(0.5))
                            .padding(.bottom, 32)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(L10n.t(.createTitle, lang))
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.createHeroQuestion, lang))
                .font(.title2.bold())
                .foregroundStyle(VovoTheme.cream)
            Text(L10n.t(.createHeroHint, lang))
                .font(.subheadline)
                .foregroundStyle(VovoTheme.cream.opacity(0.75))
        }
    }

    @ViewBuilder
    private var capabilityBanners: some View {
        let profile = DeviceProfile.current
        let graphics = profile.availability(for: .graphicsPipeline, lang: lang)
        let fm = profile.availability(for: .foundationModelsStory, lang: lang)

        if !graphics.isUsable {
            capabilityBanner(
                icon: "paintbrush.pointed",
                text: graphics.userMessage(lang)
            )
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
                .foregroundStyle(VovoTheme.cream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VovoTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(VovoTheme.amber.opacity(0.35))
                )
        )
    }

    private var photoBlock: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(VovoTheme.cardFill)
                    .frame(width: 120, height: 120)
                if let photoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    Image(systemName: "camera.fill")
                        .font(.title)
                        .foregroundStyle(VovoTheme.amber)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        photoData == nil ? L10n.t(.createPhotoOptional, lang) : L10n.t(.createChangePhoto, lang),
                        systemImage: "photo"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VovoTheme.deepNight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(VovoTheme.amber))
                }

                if photoData != nil {
                    Button(L10n.t(.createRemove, lang)) {
                        photoItem = nil
                        photoData = nil
                        photoImage = nil
                    }
                    .font(.caption)
                    .foregroundStyle(VovoTheme.softPink)
                }

                Text(L10n.t(.createOnDeviceOnly, lang))
                    .font(.caption2)
                    .foregroundStyle(VovoTheme.cream.opacity(0.45))
            }
        }
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.createDescription, lang))
                .font(.headline)
                .foregroundStyle(VovoTheme.cream)

            TextField(
                L10n.t(.createDescriptionPlaceholder, lang),
                text: $actorDescription,
                axis: .vertical
            )
            .lineLimit(4...8)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(VovoTheme.cardFill)
            )
            .foregroundStyle(VovoTheme.cream)
            .tint(VovoTheme.amber)
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
    QuickCreateStoryView(selectedTab: .constant(.create))
        .environment(LanguageStore())
        .modelContainer(for: [Story.self, StoryPage.self], inMemory: true)
}

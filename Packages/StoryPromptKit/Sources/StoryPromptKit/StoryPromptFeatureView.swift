import SwiftUI
import VovoUI

/// UI surface for the Story Prompt feature (used by main app + DEBUG harness).
public struct StoryPromptFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore
    @State private var promptText = ""
    @State private var isGenerating = false
    @State private var draft: StoryDraft?
    @State private var errorMessage: String?
    @State private var generator: any StoryFromPromptGenerating

    public init(generator: (any StoryFromPromptGenerating)? = nil) {
        // Default: on-device LiteRT-LM when its model is present, else offline fallback.
        // Both apps inherit this; `StoryPromptDebug` injects an explicit generator + download UI.
        _generator = State(initialValue: generator ?? OfflineFirstStoryGenerator())
    }

    private var lang: AppLanguage { languageStore.language }

    private var seed: StorySeedPrompt {
        StorySeedPrompt(text: promptText, language: lang)
    }

    private var wordCount: Int { seed.wordCount }

    private var canGenerate: Bool { seed.isValid && !isGenerating }

    public var body: some View {
        VStack(spacing: 0) {
            LanguageBar()

            ScrollViewReader { proxy in
                VovoScreen(
                    title: VovoL10n.t(.storySeedTitle, lang),
                    subtitle: VovoL10n.seedSubtitle(
                        min: StorySeedPrompt.minWords,
                        max: StorySeedPrompt.maxWords,
                        lang: lang
                    ),
                    scrolls: true
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField(
                            VovoL10n.t(.storySeedPlaceholder, lang),
                            text: $promptText,
                            axis: .vertical
                        )
                        .lineLimit(4...8)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .vovoCardField()
                        .accessibilityIdentifier("storySeedField")

                        HStack {
                            Text(VovoL10n.wordCount(
                                current: wordCount,
                                max: StorySeedPrompt.maxWords,
                                lang: lang
                            ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(wordCountLabelColor)
                            .accessibilityIdentifier("wordCountLabel")
                            Spacer()
                            if wordCount > 0, wordCount < StorySeedPrompt.minWords {
                                Text(VovoL10n.needMinWords(StorySeedPrompt.minWords, lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(VovoTheme.softPink)
                            } else if wordCount > StorySeedPrompt.maxWords {
                                Text(VovoL10n.tooLong(max: StorySeedPrompt.maxWords, lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(VovoTheme.softPink)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(VovoTheme.softPink)
                        }

                        Button {
                            Task { await generate() }
                        } label: {
                            if isGenerating {
                                ProgressView()
                                    .tint(VovoTheme.deepNight)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            } else {
                                Text(VovoL10n.t(.storyCreate, lang))
                            }
                        }
                        .buttonStyle(VovoPrimaryButtonStyle(enabled: canGenerate))
                        .disabled(!canGenerate)
                        .accessibilityIdentifier("createStoryButton")

                        if let draft {
                            storyResult(draft)
                                .id("storyResult")
                                .accessibilityIdentifier("storyResult")
                        }
                    }
                }
                .onChange(of: draft?.id) { _, newID in
                    guard newID != nil else { return }
                    // Bring the story into view after generation (form stays above).
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("storyResult", anchor: .top)
                    }
                }
            }
        }
        // Clear generated draft when language changes so UI language and body stay aligned.
        .onChange(of: languageStore.language) { _, _ in
            draft = nil
            errorMessage = nil
        }
    }

    private var wordCountLabelColor: Color {
        if seed.isValid { return VovoTheme.mint }
        if wordCount == 0 { return VovoTheme.cream.opacity(0.5) }
        return VovoTheme.amber
    }

    /// Full story body as a simple stack — parent `VovoScreen` ScrollView owns scrolling.
    @ViewBuilder
    private func storyResult(_ draft: StoryDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.title)
                .font(.title3.bold())
                .foregroundStyle(VovoTheme.amber)
                .fixedSize(horizontal: false, vertical: true)

            Text(draft.summary)
                .font(.subheadline)
                .foregroundStyle(VovoTheme.cream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(draft.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                VStack(alignment: .leading, spacing: 4) {
                    Text(VovoL10n.scene(index + 1, lang: draft.language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(VovoTheme.mint.opacity(0.9))
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(VovoTheme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VovoTheme.cardFill)
                )
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    @MainActor
    private func generate() async {
        errorMessage = nil
        draft = nil
        let seed = StorySeedPrompt(text: promptText, language: lang)
        do {
            try seed.validate()
        } catch let e as StorySeedPrompt.ValidationError {
            errorMessage = validationMessage(e)
            return
        } catch {
            errorMessage = VovoL10n.t(.storyInvalidPrompt, lang)
            return
        }

        isGenerating = true
        defer { isGenerating = false }
        do {
            draft = try await generator.generate(from: seed)
        } catch let e as StorySeedPrompt.ValidationError {
            errorMessage = validationMessage(e)
        } catch {
            errorMessage = VovoL10n.t(.storyGenerateFailed, lang)
        }
    }

    private func validationMessage(_ error: StorySeedPrompt.ValidationError) -> String {
        switch error {
        case .tooShort(let n):
            return VovoL10n.validationTooShort(
                min: StorySeedPrompt.minWords,
                current: n,
                lang: lang
            )
        case .tooLong(let n):
            return VovoL10n.validationTooLong(
                max: StorySeedPrompt.maxWords,
                current: n,
                lang: lang
            )
        }
    }
}

#Preview {
    StoryPromptFeatureView()
        .environment(LanguageStore(preferenceRaw: AppLanguage.englishUS.rawValue))
}

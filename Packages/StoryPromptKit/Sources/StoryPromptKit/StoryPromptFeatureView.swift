import SwiftUI
import VovoUI

/// Whether the on-device story model is available for the create flow.
enum StoryModelGateState: Equatable {
    case checking
    case ready
    case needsModel
    case downloading(progress: Double)
    case importing
    case failed(message: String)
    case halted
}

/// UI surface for the Story Prompt feature (used by main app + DEBUG harness).
///
/// On open, checks for the LiteRT-LM model. If missing, offers **automatic download** from
/// our host (`files.kraftek.dev`). If that fails, Hugging Face is a **manual browser fallback**,
/// plus **Import** from Files/Downloads.
public struct StoryPromptFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore
    @Environment(\.openURL) private var openURL
    @State private var promptText = ""
    @State private var isGenerating = false
    @State private var draft: StoryDraft?
    @State private var errorMessage: String?
    @State private var generator: any StoryFromPromptGenerating
    @State private var modelStore: LiteRTLMModelStore
    @State private var modelGate: StoryModelGateState = .checking
    @State private var showFileImporter = false

    public init(
        generator: (any StoryFromPromptGenerating)? = nil,
        modelStore: LiteRTLMModelStore = LiteRTLMModelStore()
    ) {
        let store = modelStore
        _modelStore = State(initialValue: store)
        _generator = State(initialValue: generator ?? DeviceStoryGenerator(modelStore: store))
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

            switch modelGate {
            case .checking:
                gateChecking
            case .ready:
                createFlow
            case .needsModel:
                gateNeedsModel
            case .downloading(let progress):
                gateDownloading(progress: progress)
            case .importing:
                gateImporting
            case .failed(let message):
                gateFailed(message: message)
            case .halted:
                gateHalted
            }
        }
        .task { await refreshModelGate() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImportResult(result) }
        }
        .onChange(of: languageStore.language) { _, _ in
            draft = nil
            errorMessage = nil
        }
    }

    // MARK: - Model gate screens

    private var gateChecking: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateChecking, lang),
            scrolls: false
        ) {
            ProgressView()
                .tint(VovoTheme.amber)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("modelGateChecking")
        }
    }

    private var gateNeedsModel: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateBody, lang),
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(VovoL10n.t(.storyModelGateFilenameHint, lang))
                    .font(.caption)
                    .foregroundStyle(VovoTheme.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await startModelDownload() }
                } label: {
                    Text(VovoL10n.t(.storyModelGateDownload, lang))
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
                .accessibilityIdentifier("modelGateDownload")

                Button {
                    showFileImporter = true
                } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("modelGateImport")

                Button {
                    openFallbackHostPage()
                } label: {
                    Text(VovoL10n.t(.storyModelGateOpenFallback, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("modelGateOpenFallback")

                Button {
                    modelGate = .halted
                } label: {
                    Text(VovoL10n.t(.storyModelGateNotNow, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("modelGateDecline")
            }
        }
    }

    private func gateDownloading(progress: Double) -> some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateDownloading, lang),
            scrolls: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)
                ProgressView(value: max(progress, 0.02)) {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(VovoTheme.cream.opacity(0.85))
                }
                .tint(VovoTheme.amber)
                .accessibilityIdentifier("modelGateProgress")
                Spacer(minLength: 0)
            }
        }
    }

    private var gateImporting: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateImporting, lang),
            scrolls: false
        ) {
            ProgressView()
                .tint(VovoTheme.amber)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("modelGateImporting")
        }
    }

    private func gateFailed(message: String) -> some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: message,
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    Task { await startModelDownload() }
                } label: {
                    Text(VovoL10n.t(.storyModelGateRetry, lang))
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
                .accessibilityIdentifier("modelGateRetry")

                Button {
                    openFallbackHostPage()
                } label: {
                    Text(VovoL10n.t(.storyModelGateOpenFallback, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("modelGateOpenFallback")

                Button {
                    showFileImporter = true
                } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())

                Button {
                    modelGate = .halted
                } label: {
                    Text(VovoL10n.t(.storyModelGateNotNow, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
            }
        }
    }

    private var gateHalted: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateHaltedTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateHaltedBody, lang),
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    Task { await startModelDownload() }
                } label: {
                    Text(VovoL10n.t(.storyModelGateDownload, lang))
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
                .accessibilityIdentifier("modelGateDownloadAgain")

                Button {
                    showFileImporter = true
                } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())

                Button {
                    openFallbackHostPage()
                } label: {
                    Text(VovoL10n.t(.storyModelGateOpenFallback, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Create flow (model ready)

    private var createFlow: some View {
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
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo("storyResult", anchor: .top)
                }
            }
        }
    }

    private var wordCountLabelColor: Color {
        if seed.isValid { return VovoTheme.mint }
        if wordCount == 0 { return VovoTheme.cream.opacity(0.5) }
        return VovoTheme.amber
    }

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

    // MARK: - Actions

    @MainActor
    private func refreshModelGate() async {
        modelGate = .checking
        if await modelStore.isModelPresent() {
            modelGate = .ready
            return
        }
        if let imported = try? await modelStore.tryImportFromDownloadsDirectory(), imported {
            modelGate = .ready
            return
        }
        modelGate = .needsModel
    }

    @MainActor
    private func startModelDownload() async {
        modelGate = .downloading(progress: 0)
        do {
            try await modelStore.download { fraction in
                modelGate = .downloading(progress: min(max(fraction, 0), 1))
            }
            modelGate = await modelStore.isModelPresent()
                ? .ready
                : .failed(message: VovoL10n.t(.storyGenerateFailed, lang))
        } catch {
            let msg = error.localizedDescription
            modelGate = .failed(
                message: msg.isEmpty ? VovoL10n.t(.storyGenerateFailed, lang) : msg
            )
        }
    }

    private func openFallbackHostPage() {
        openURL(LiteRTLMModelStore.defaultHostFallbackPageURL)
    }

    @MainActor
    private func handleImportResult(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure:
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            modelGate = .importing
            do {
                try await modelStore.importModel(from: url)
                modelGate = await modelStore.isModelPresent()
                    ? .ready
                    : .failed(message: LiteRTLMModelStore.ImportError.copyFailed.localizedDescription)
            } catch {
                let msg = error.localizedDescription
                modelGate = .failed(
                    message: msg.isEmpty ? VovoL10n.t(.storyGenerateFailed, lang) : msg
                )
            }
        }
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
        } catch let e as StoryPromptError {
            switch e {
            case .modelNotInstalled:
                errorMessage = VovoL10n.t(.storyModelNotInstalled, lang)
                modelGate = .needsModel
            case .generationFailed, .invalidPrompt:
                errorMessage = VovoL10n.t(.storyGenerateFailed, lang)
            }
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

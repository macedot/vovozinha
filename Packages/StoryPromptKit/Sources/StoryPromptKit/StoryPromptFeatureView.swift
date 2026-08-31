import SwiftUI
import VovoUI

/// Whether the on-device story model is available for the create flow.
enum StoryModelGateState: Equatable {
    case checking
    case ready
    case needsModel
    case downloading(ModelDownloadProgress)
    case importing
    case failed(message: String)
    case halted
}

/// UI surface for the Story Prompt feature (used by main app + DEBUG harness).
///
/// On open, checks for the **Qwen3.5-4B MLX** model pack in private Application Support.
/// If missing, offers **automatic download** from `vovo.kraftek.cloud`, plus **Import**
/// via the system document picker (copied into app storage — not kept in
/// Documents/Downloads). There is no Hugging Face fallback.
public struct StoryPromptFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore
    @State private var promptText = ""
    @State private var isGenerating = false
    @State private var draft: StoryDraft?
    @State private var errorMessage: String?
    @State private var generator: any StoryFromPromptGenerating
    @State private var modelStore: OnDeviceMLXModelStore
    @State private var modelGate: StoryModelGateState = .checking
    @State private var showFileImporter = false
    @State private var modelUpdateAvailable = false
    @State private var showRemoveModelConfirm = false
    @FocusState private var isSeedFieldFocused: Bool

    public init(
        generator: (any StoryFromPromptGenerating)? = nil,
        modelStore: OnDeviceMLXModelStore = OnDeviceMLXModelStore()
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
            case .downloading(let snapshot):
                gateDownloading(snapshot)
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
        .alert(
            VovoL10n.t(.storyModelRemoveConfirmTitle, lang),
            isPresented: $showRemoveModelConfirm
        ) {
            Button(VovoL10n.t(.storyModelRemoveCancel, lang), role: .cancel) {}
            Button(VovoL10n.t(.storyModelRemoveConfirmAction, lang), role: .destructive) {
                Task { await removeInstalledModel() }
            }
        } message: {
            Text(VovoL10n.t(.storyModelRemoveConfirmBody, lang))
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
                    modelGate = .halted
                } label: {
                    Text(VovoL10n.t(.storyModelGateNotNow, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("modelGateDecline")
            }
        }
    }

    private func gateDownloading(_ snapshot: ModelDownloadProgress) -> some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: downloadPhaseSubtitle(snapshot),
            scrolls: false
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)

                if snapshot.bytesTotal != nil || snapshot.fraction > 0 {
                    ProgressView(value: max(snapshot.fraction, 0.02)) {
                        Text("\(Int(snapshot.fraction * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VovoTheme.cream.opacity(0.85))
                    }
                    .tint(VovoTheme.amber)
                    // Force refresh when bytes move (some OS versions coalesce ProgressView).
                    .id(snapshot.bytesReceived)
                    .animation(.linear(duration: 0.15), value: snapshot.fraction)
                    .accessibilityIdentifier("modelGateProgress")
                } else {
                    ProgressView()
                        .tint(VovoTheme.amber)
                        .accessibilityIdentifier("modelGateProgress")
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let total = snapshot.formattedTotal {
                        downloadStatLine(
                            VovoL10n.downloadBytes(
                                received: snapshot.formattedReceived,
                                total: total,
                                lang: lang
                            )
                        )
                    } else if snapshot.bytesReceived > 0 {
                        downloadStatLine(snapshot.formattedReceived)
                    }

                    if snapshot.phase == .downloading, snapshot.bytesPerSecond > 0 {
                        downloadStatLine(
                            VovoL10n.downloadSpeed(snapshot.formattedSpeed, lang: lang)
                        )
                    }

                    downloadStatLine(
                        VovoL10n.downloadElapsed(snapshot.formattedElapsed, lang: lang)
                    )

                    if snapshot.phase == .downloading {
                        if let eta = snapshot.formattedETA {
                            downloadStatLine(VovoL10n.downloadETA(eta, lang: lang))
                        } else if snapshot.bytesReceived > 0 {
                            downloadStatLine(VovoL10n.t(.storyModelGateDownloadETAUnknown, lang))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("modelGateDownloadStats")

                Spacer(minLength: 0)
            }
        }
    }

    private func downloadPhaseSubtitle(_ snapshot: ModelDownloadProgress) -> String {
        switch snapshot.phase {
        case .downloading:
            return VovoL10n.t(.storyModelGateDownloading, lang)
        case .verifying:
            return VovoL10n.t(.storyModelGateVerifying, lang)
        case .unpacking:
            return VovoL10n.t(.storyModelGateUnpacking, lang)
        case .finished:
            return VovoL10n.t(.storyModelGateDownloading, lang)
        }
    }

    private func downloadStatLine(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(VovoTheme.cream.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
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
                    if modelUpdateAvailable {
                        modelUpdateBanner
                    }

                    TextField(
                        VovoL10n.t(.storySeedPlaceholder, lang),
                        text: $promptText,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .vovoCardField()
                    .focused($isSeedFieldFocused)
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

                    Button {
                        showRemoveModelConfirm = true
                    } label: {
                        Text(VovoL10n.t(.storyModelRemove, lang))
                    }
                    .buttonStyle(VovoSecondaryButtonStyle())
                    .disabled(isGenerating)
                    .accessibilityIdentifier("removeModelButton")

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

    private var modelUpdateBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(VovoL10n.t(.storyModelUpdateTitle, lang))
                .font(.headline)
                .foregroundStyle(VovoTheme.amber)
            Text(VovoL10n.t(.storyModelUpdateBody, lang))
                .font(.subheadline)
                .foregroundStyle(VovoTheme.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await startModelDownload() }
            } label: {
                Text(VovoL10n.t(.storyModelUpdateAction, lang))
            }
            .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
            .accessibilityIdentifier("modelUpdateAction")

            Button {
                modelUpdateAvailable = false
            } label: {
                Text(VovoL10n.t(.storyModelUpdateLater, lang))
            }
            .buttonStyle(VovoSecondaryButtonStyle())
            .accessibilityIdentifier("modelUpdateLater")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VovoTheme.cardFill)
        )
        .accessibilityIdentifier("modelUpdateBanner")
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
            modelUpdateAvailable = await modelStore.checkForHostUpdate()
            return
        }
        modelUpdateAvailable = false
        modelGate = .needsModel
    }

    @MainActor
    private func startModelDownload() async {
        modelGate = .downloading(.zero)
        do {
            try await modelStore.download { snapshot in
                modelGate = .downloading(snapshot)
            }
            if await modelStore.isModelPresent() {
                modelUpdateAvailable = false
                modelGate = .ready
            } else {
                modelGate = .failed(message: VovoL10n.t(.storyGenerateFailed, lang))
            }
        } catch {
            let msg = error.localizedDescription
            modelGate = .failed(
                message: msg.isEmpty ? VovoL10n.t(.storyGenerateFailed, lang) : msg
            )
        }
    }

    @MainActor
    private func removeInstalledModel() async {
        do {
            try await modelStore.removeModel()
        } catch {
            #if DEBUG
            print("[StoryPrompt] removeModel failed: \(error)")
            #endif
        }
        draft = nil
        errorMessage = nil
        modelUpdateAvailable = false
        modelGate = .needsModel
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
                modelUpdateAvailable = false
                modelGate = await modelStore.isModelPresent()
                    ? .ready
                    : .failed(message: OnDeviceMLXModelStore.ImportError.copyFailed.localizedDescription)
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

        isSeedFieldFocused = false
        isGenerating = true
        defer { isGenerating = false }

        // Transient MLX / parse failures are common; retry automatically, then let the parent tap Create again.
        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            do {
                draft = try await generator.generate(from: seed)
                return
            } catch let e as StorySeedPrompt.ValidationError {
                errorMessage = validationMessage(e)
                return
            } catch let e as StoryPromptError {
                switch e {
                case .modelNotInstalled:
                    errorMessage = VovoL10n.t(.storyModelNotInstalled, lang)
                    modelGate = .needsModel
                    return
                case .invalidPrompt:
                    errorMessage = VovoL10n.t(.storyInvalidPrompt, lang)
                    return
                case .generationFailed:
                    #if DEBUG
                    print("[StoryPrompt] generate attempt \(attempt)/\(maxAttempts) failed")
                    #endif
                    if attempt == maxAttempts {
                        errorMessage = VovoL10n.t(.storyGenerateFailed, lang)
                    }
                }
            } catch {
                #if DEBUG
                print("[StoryPrompt] generate attempt \(attempt)/\(maxAttempts) failed: \(error)")
                #endif
                if attempt == maxAttempts {
                    errorMessage = VovoL10n.t(.storyGenerateFailed, lang)
                }
            }
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

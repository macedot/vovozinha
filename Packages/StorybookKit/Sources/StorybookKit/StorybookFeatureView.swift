import StoryPromptKit
import SwiftUI
import VovoUI

private enum Gate {
    case checking
    case needsStoryModel
    case downloadingStory(fraction: Double)
    case importing
    case failed(String)
    case ready
}

private enum Screen {
    case create
    case history
    case reader
}

/// Product create + reader: a required description, 10 text pages.
public struct StorybookFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore

    @State private var gate: Gate = .checking
    @State private var storyStore = OnDeviceMLXModelStore()
    @State private var showFileImporter = false

    @State private var promptText = ""
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var title: String = ""
    @State private var summary: String = ""
    @State private var pages: [StoryPage] = []
    @State private var storyID = UUID()
    @State private var storyCreatedAt = Date()
    @State private var activeSeedPrompt = ""
    @State private var activeLanguage: AppLanguage = .englishUS
    @State private var pipelineTask: Task<Void, Never>?
    @State private var phase: PipelinePhase = .story
    @State private var screen: Screen = .create
    /// Where the Back chevron in the reader returns to: `.create` after a fresh
    /// generation, `.history` when the book was opened from Story History.
    @State private var readerOrigin: Screen = .create
    @State private var historyBooks: [Storybook] = []
    @FocusState private var seedFocused: Bool
    private let historyStore: StoryHistoryStore

    public init(historyStore: StoryHistoryStore = StoryHistoryStore()) {
        self.historyStore = historyStore
    }

    private var lang: AppLanguage { languageStore.language }

    private var seed: StorySeedPrompt {
        StorySeedPrompt(text: promptText, language: lang)
    }

    private var isGateReady: Bool {
        if case .ready = gate { return true }
        return false
    }

    private var canCreate: Bool { seed.isValid && !isRunning && isGateReady }

    public var body: some View {
        VStack(spacing: 0) {
            LanguageBar()
            switch gate {
            case .checking:
                VovoScreen(title: VovoL10n.t(.storyModelGateChecking, lang), scrolls: false) {
                    ProgressView().tint(VovoTheme.amber)
                }
            case .needsStoryModel:
                storyModelGate
            case .downloadingStory(let fraction):
                downloadingScreen(title: VovoL10n.t(.storyModelGateTitle, lang), fraction: fraction)
            case .importing:
                VovoScreen(title: VovoL10n.t(.storyModelGateImporting, lang), scrolls: false) {
                    ProgressView().tint(VovoTheme.amber)
                }
            case .failed(let message):
                failedGate(message)
            case .ready:
                switch screen {
                case .create: createFlow
                case .history: historyScreen
                case .reader: reader
                }
            }
        }
        .task { await refreshGate() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .onDisappear {
            pipelineTask?.cancel()
            setIdleTimer(false)
        }
    }

    private var storyModelGate: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateBody, lang)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(VovoL10n.t(.storyModelGateFilenameHint, lang))
                    .font(.caption)
                    .foregroundStyle(VovoTheme.cream.opacity(0.75))
                Button {
                    Task { await downloadStoryModel() }
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
            }
        }
    }

    private func downloadingScreen(title: String, fraction: Double) -> some View {
        VovoScreen(title: title, scrolls: false) {
            ProgressView(value: max(fraction, 0.02))
                .tint(VovoTheme.amber)
        }
    }

    private func failedGate(_ message: String) -> some View {
        VovoScreen(title: VovoL10n.t(.storyModelGateTitle, lang), subtitle: message) {
            Button {
                Task { await refreshGate() }
            } label: {
                Text(VovoL10n.t(.storyModelGateRetry, lang))
            }
            .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
        }
    }

    private var createFlow: some View {
        VovoScreen(
            title: VovoL10n.t(.storySeedTitle, lang),
            subtitle: VovoL10n.t(.storySeedSubtitle, lang)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                TextField("", text: $promptText, axis: .vertical)
                    .lineLimit(4...8)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .vovoCardField()
                    .focused($seedFocused)
                    .accessibilityIdentifier("storySeedField")

                HStack {
                    Text(VovoL10n.wordCount(
                        current: seed.wordCount,
                        max: StorySeedPrompt.maxWords,
                        lang: lang
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(seed.isValid ? VovoTheme.mint : VovoTheme.cream.opacity(0.6))
                    Spacer()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(VovoTheme.softPink)
                }

                Button {
                    Task { await startPipeline() }
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView().tint(VovoTheme.deepNight)
                            Text(runningLabel)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(VovoL10n.t(.storyCreate, lang))
                    }
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: canCreate))
                .disabled(!canCreate)
                .accessibilityIdentifier("createStoryButton")

                Button {
                    loadHistory()
                    screen = .history
                } label: {
                    Text(VovoL10n.t(.storyHistoryButton, lang)).frame(maxWidth: .infinity)
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("storyHistoryButton")
            }
        }
    }

    private var runningLabel: String {
        switch phase {
        case .story:
            return VovoL10n.t(.storyWriting, lang)
        case .finished, .failed:
            return VovoL10n.t(.storyCreate, lang)
        }
    }

    private var reader: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(VovoTheme.softPink)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if !activeSeedPrompt.isEmpty {
                StoryOriginalDescription(text: activeSeedPrompt, lang: lang)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            TabView {
                ForEach(pages) { page in
                    VovoScreen(
                        title: title.isEmpty ? VovoL10n.t(.storyScene, lang) : title,
                        subtitle: summary,
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
            .accessibilityIdentifier("storyResult")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    navBackButton(destination: readerOrigin, identifier: "readerBackButton")
                }
            }
            #endif
            readerActionBar
        }
    }

    private var readerActionBar: some View {
        Button {
            startNewStory()
        } label: {
            Text(VovoL10n.t(.readerNewStory, lang))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
        .accessibilityIdentifier("newStoryButton")
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var historyScreen: some View {
        VovoScreen(
            title: VovoL10n.t(.storyHistoryTitle, lang),
            scrolls: true
        ) {
            if historyBooks.isEmpty {
                Text(VovoL10n.t(.storyHistoryEmpty, lang))
                    .font(.body)
                    .foregroundStyle(VovoTheme.cream.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .accessibilityIdentifier("storyHistoryEmpty")
            } else {
                VStack(spacing: 12) {
                    ForEach(historyBooks) { book in
                        historyRow(book)
                    }
                }
                .accessibilityIdentifier("storyHistoryList")
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                navBackButton(destination: .create, identifier: "storyHistoryBackButton")
            }
        }
        #endif
    }

    private func historyRow(_ book: Storybook) -> some View {
        HStack(spacing: 12) {
            Button {
                openBook(book)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(VovoTheme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title.isEmpty ? VovoL10n.t(.storyScene, lang) : book.title)
                            .font(.headline)
                            .foregroundStyle(VovoTheme.cream)
                            .lineLimit(2)
                        Text(book.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(VovoTheme.cream.opacity(0.7))
                        Text(VovoL10n.historyPageCount(book.pages.count, lang: lang))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VovoTheme.mint)
                        let preview = book.seedPrompt.isEmpty ? book.summary : book.seedPrompt
                        if !preview.isEmpty {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(VovoTheme.cream.opacity(0.72))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("storyHistoryItem_\(book.id.uuidString)")

            Button {
                deleteBook(book)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(VovoTheme.softPink)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("storyHistoryDelete_\(book.id.uuidString)")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VovoTheme.cardFill)
        )
    }

    @MainActor
    private func refreshGate() async {
        gate = .checking
        if await !storyStore.isModelPresent() {
            gate = .needsStoryModel
            return
        }
        gate = .ready
    }

    @MainActor
    private func downloadStoryModel() async {
        do {
            try await storyStore.download { snap in
                gate = .downloadingStory(fraction: snap.fraction)
            }
            await refreshGate()
        } catch {
            gate = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure:
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            gate = .importing
            do {
                try await storyStore.importModel(from: url)
                await refreshGate()
            } catch {
                gate = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Navigation (create / history / reader)

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Navigation-bar back chevron shared by History and Reader.
    private func navBackButton(destination: Screen, identifier: String) -> some View {
        Button {
            goBack(to: destination)
        } label: {
            Label(VovoL10n.t(.readerBack, lang), systemImage: "chevron.left")
        }
        .accessibilityIdentifier(identifier)
    }

    /// Returns to Create keeping the current draft so it can be tweaked.
    @MainActor
    private func goBack(to destination: Screen) {
        screen = destination
    }

    /// Starts over: cancels any running pipeline and clears the draft.
    @MainActor
    private func startNewStory() {
        pipelineTask?.cancel()
        promptText = ""
        pages = []
        title = ""
        summary = ""
        activeSeedPrompt = ""
        errorMessage = nil
        phase = .story
        isRunning = false
        setIdleTimer(false)
        readerOrigin = .create
        screen = .create
    }

    private func loadHistory() {
        let fromFiles = StoryFileStore(rootURL: documentsURL).loadAllStorybooks()
        let fromHistory = (try? historyStore.load()) ?? []
        var byID: [UUID: Storybook] = [:]
        for book in fromFiles {
            byID[book.id] = book
        }
        for book in fromHistory {
            guard let file = byID[book.id] else {
                byID[book.id] = book
                continue
            }
            var chosen = book
            if chosen.pages.isEmpty { chosen.pages = file.pages }
            if chosen.seedPrompt.isEmpty { chosen.seedPrompt = file.seedPrompt }
            if chosen.title.isEmpty { chosen.title = file.title }
            byID[book.id] = chosen
        }
        historyBooks = byID.values.sorted { $0.createdAt > $1.createdAt }
    }

    @MainActor
    private func openBook(_ book: Storybook) {
        pipelineTask?.cancel()
        isRunning = false
        setIdleTimer(false)
        errorMessage = nil
        storyID = book.id
        storyCreatedAt = book.createdAt
        title = book.title
        summary = book.summary
        activeSeedPrompt = book.seedPrompt
        activeLanguage = AppLanguage.resolve(preferenceRaw: book.language)
        pages = book.pages
        readerOrigin = .history
        screen = .reader
    }

    private func deleteBook(_ book: Storybook) {
        if isRunning && book.id == storyID {
            pipelineTask?.cancel()
            isRunning = false
            setIdleTimer(false)
        }
        try? historyStore.delete(book)
        loadHistory()
    }

    @MainActor
    private func startPipeline() async {
        pipelineTask?.cancel()
        errorMessage = nil
        isRunning = true
        phase = .story
        setIdleTimer(true)
        let id = UUID()
        storyID = id
        storyCreatedAt = Date()
        activeSeedPrompt = seed.trimmed
        activeLanguage = seed.language
        pages = []
        title = ""
        summary = ""
        let pipeline = SeedPipeline(
            storyGenerator: DeviceStoryGenerator(modelStore: storyStore),
            store: StoryFileStore(rootURL: documentsURL)
        )
        let seedPrompt = seed
        pipelineTask = Task {
            for await event in pipeline.run(seed: seedPrompt, storyID: id) {
                await MainActor.run { apply(event) }
            }
            await MainActor.run {
                isRunning = false
                setIdleTimer(false)
            }
        }
    }

    @MainActor
    private func apply(_ event: PipelineEvent) {
        switch event {
        case .phaseChanged(let newPhase):
            phase = newPhase
        case .pageTextsReady(let readyPages, let readyTitle, let readySummary):
            pages = readyPages
            title = readyTitle
            summary = readySummary
            persistStory(
                phase: .story,
                pages: readyPages,
                title: readyTitle,
                summary: readySummary
            )
            readerOrigin = .create
            screen = .reader
        case .failed(let message):
            let fallback = pages.isEmpty
                ? VovoL10n.t(.storyGenerateFailed, lang)
                : VovoL10n.t(.storyPipelineFailed, lang)
            #if DEBUG
            errorMessage = message.isEmpty ? fallback : "\(fallback) (\(message))"
            #else
            errorMessage = fallback
            #endif
            isRunning = false
            setIdleTimer(false)
            persistStory(phase: .failed)
        case .finished:
            persistStory(phase: .finished)
        }
    }

    private func persistStory(
        phase: PipelinePhase,
        pages: [StoryPage]? = nil,
        title: String? = nil,
        summary: String? = nil
    ) {
        let storyPages = pages ?? self.pages
        guard !storyPages.isEmpty else { return }
        let story = Storybook(
            id: storyID,
            title: title ?? self.title,
            summary: summary ?? self.summary,
            language: activeLanguage.rawValue,
            seedPrompt: activeSeedPrompt,
            phase: phase,
            pages: storyPages,
            createdAt: storyCreatedAt
        )
        do {
            try historyStore.upsert(story)
        } catch {
            errorMessage = VovoL10n.t(.storyHistorySaveFailed, lang)
            #if DEBUG
            print("[Storybook] history save failed: \(error)")
            #endif
        }
    }

    private func setIdleTimer(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

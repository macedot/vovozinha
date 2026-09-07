import ImageGenKit
import PhotosUI
import PhotoDescribeKit
import StoryPromptKit
import SwiftUI
import VovoUI

#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

private enum DualGate {
    case checking
    case needsStoryModel
    case needsImagePack
    case downloadingStory(fraction: Double)
    case downloadingImage(fraction: Double)
    case importing
    case failed(String)
    case ready
}

private enum ImporterTarget {
    case storyModel
    case imagePack
}

private enum Screen {
    case create
    case history
    case reader
}

/// Product create + reader: seed, optional photo, 10 illustrated pages.
public struct StorybookFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore

    @State private var gate: DualGate = .checking
    @State private var storyStore = OnDeviceMLXModelStore()
    @State private var imageStore = CoreMLImagePackStore()
    @State private var showFileImporter = false
    @State private var importerTarget: ImporterTarget = .storyModel

    @State private var promptText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
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
            case .needsImagePack:
                imagePackGate
            case .downloadingStory(let fraction):
                downloadingScreen(title: VovoL10n.t(.storyModelGateTitle, lang), fraction: fraction)
            case .downloadingImage(let fraction):
                downloadingScreen(title: VovoL10n.t(.imagePackGateTitle, lang), fraction: fraction)
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
                    importerTarget = .storyModel
                    showFileImporter = true
                } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("modelGateImport")
            }
        }
    }

    private var imagePackGate: some View {
        VovoScreen(
            title: VovoL10n.t(.imagePackGateTitle, lang),
            subtitle: VovoL10n.t(.imagePackGateBody, lang)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(VovoL10n.t(.imagePackGateFilenameHint, lang))
                    .font(.caption)
                    .foregroundStyle(VovoTheme.cream.opacity(0.75))
                Button {
                    Task { await downloadImagePack() }
                } label: {
                    Text(VovoL10n.t(.imagePackGateDownload, lang))
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
                .accessibilityIdentifier("imagePackDownload")
                Button {
                    importerTarget = .imagePack
                    showFileImporter = true
                } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
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

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(VovoL10n.t(.storyAddPhoto, lang)).frame(maxWidth: .infinity)
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("storyAddPhoto")
                .onChange(of: pickerItem) { _, item in
                    Task { await loadPhoto(item) }
                }

                if let photoData, let image = uiImage(from: photoData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        self.photoData = nil
                        pickerItem = nil
                    } label: {
                        Text(VovoL10n.t(.storyClearPhoto, lang))
                    }
                    .buttonStyle(VovoSecondaryButtonStyle())
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
        case .caption, .bible, .story:
            return VovoL10n.t(.storyWriting, lang)
        case .illustrationPrompts, .reference, .pages:
            return VovoL10n.t(.storyPreparingPictures, lang)
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
            TabView {
                ForEach(pages) { page in
                    VovoScreen(
                        title: title.isEmpty ? VovoL10n.t(.storyScene, lang) : title,
                        subtitle: summary,
                        scrolls: true
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            pageArt(page)
                            Text(page.text)
                                .font(.body)
                                .foregroundStyle(VovoTheme.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
            historyThumbnail(book)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title.isEmpty ? VovoL10n.t(.storyScene, lang) : book.title)
                    .font(.headline)
                    .foregroundStyle(VovoTheme.cream)
                    .lineLimit(2)
                Text(book.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(VovoTheme.cream.opacity(0.7))
                Text(VovoL10n.historyPages(
                    illustrated: book.pages.filter { $0.imageFileName != nil }.count,
                    total: max(book.pages.count, 1),
                    lang: lang
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(VovoTheme.mint)
            }
            Spacer()
            Button {
                deleteBook(book)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(VovoTheme.softPink)
            }
            .accessibilityIdentifier("storyHistoryDelete_\(book.id.uuidString)")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VovoTheme.cardFill)
        )
        .contentShape(Rectangle())
        .onTapGesture { openBook(book) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storyHistoryItem_\(book.id.uuidString)")
    }

    @ViewBuilder
    private func historyThumbnail(_ book: Storybook) -> some View {
        if let fileName = book.pages.compactMap(\.imageFileName).first,
           let image = loadStoryPNG(id: book.id, fileName: fileName) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VovoTheme.cream.opacity(0.12))
                Image(systemName: "book.fill")
                    .foregroundStyle(VovoTheme.cream.opacity(0.6))
            }
            .frame(width: 56, height: 56)
        }
    }

    /// Page artwork; page 1 doubles as the cover with the story title over the
    /// art. The page text itself renders BELOW the image (reader body), never
    /// on top of the artwork.
    @ViewBuilder
    private func pageArt(_ page: StoryPage) -> some View {
        if let name = page.imageFileName,
           let img = loadStoryPNG(id: storyID, fileName: name) {
            img
                .resizable()
                .scaledToFit()
                .overlay(alignment: .top) {
                    if page.index == 1 {
                        coverBanner
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VovoTheme.cardFill)
                    .frame(height: 220)
                VStack(spacing: 8) {
                    if isRunning {
                        ProgressView().tint(VovoTheme.amber)
                    }
                    Text(VovoL10n.t(.readerWaitingPicture, lang))
                        .font(.caption)
                        .foregroundStyle(VovoTheme.cream.opacity(0.7))
                }
            }
        }
    }

    private var coverBanner: some View {
        Text(title.isEmpty ? VovoL10n.t(.storyScene, lang) : title)
            .font(.title2.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(VovoTheme.cream)
            .shadow(color: .black.opacity(0.6), radius: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    @MainActor
    private func refreshGate() async {
        gate = .checking
        if await !storyStore.isModelPresent() {
            gate = .needsStoryModel
            return
        }
        if await !imageStore.isPackPresent() {
            gate = .needsImagePack
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
    private func downloadImagePack() async {
        do {
            try await imageStore.download { snap in
                gate = .downloadingImage(fraction: snap.fraction)
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
                switch importerTarget {
                case .storyModel:
                    try await storyStore.importModel(from: url)
                case .imagePack:
                    try await imageStore.importPack(from: url)
                }
                await refreshGate()
            } catch {
                gate = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { photoData = nil; return }
        photoData = try? await item.loadTransferable(type: Data.self)
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
    /// A running pipeline keeps drawing; the book is already saved on disk.
    @MainActor
    private func goBack(to destination: Screen) {
        screen = destination
    }

    /// Starts over: cancels any running pipeline and clears the draft.
    @MainActor
    private func startNewStory() {
        pipelineTask?.cancel()
        promptText = ""
        photoData = nil
        pickerItem = nil
        pages = []
        title = ""
        summary = ""
        errorMessage = nil
        phase = .story
        isRunning = false
        setIdleTimer(false)
        readerOrigin = .create
        screen = .create
    }

    private func loadHistory() {
        historyBooks = StoryFileStore(rootURL: documentsURL).loadAllStorybooks()
    }

    @MainActor
    private func openBook(_ book: Storybook) {
        pipelineTask?.cancel()
        isRunning = false
        setIdleTimer(false)
        errorMessage = nil
        storyID = book.id
        title = book.title
        summary = book.summary
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
        try? StoryFileStore(rootURL: documentsURL).deleteStory(id: book.id)
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
        let photo: PhotoDescribeInput? = photoData.map { PhotoDescribeInput(imageData: $0) }
        let pipeline = SeedPipeline(
            storyGenerator: DeviceStoryGenerator(modelStore: storyStore),
            illustrationPrompts: DeviceIllustrationPromptGenerator(
                completer: DeviceCompleterAdapter(DevicePromptCompleter(modelStore: storyStore)),
                language: lang
            ),
            imageGenerator: DeviceImageGenerator(packStore: imageStore),
            photoDescriber: DevicePhotoDescriber(modelStore: storyStore),
            memory: MemorySequencer(),
            store: StoryFileStore(rootURL: documentsURL),
            bibleGenerator: DeviceStoryBibleGenerator(
                completer: DeviceCompleterAdapter(DevicePromptCompleter(modelStore: storyStore)),
                language: lang
            )
        )
        let seedPrompt = seed
        pipelineTask = Task {
            for await event in pipeline.run(seed: seedPrompt, photo: photo, storyID: id) {
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
        case .illustrationReady(let index, let fileName):
            var updatedPages = pages
            if let i = updatedPages.firstIndex(where: { $0.index == index }) {
                updatedPages[i].imageFileName = fileName
                pages = updatedPages
                persistStory(phase: .pages, pages: updatedPages)
            }
        case .progress:
            break
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
            characterDescriptor: "",
            baseSeed: StoryIdentity.baseSeed(storyID: storyID),
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

    private func uiImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #endif
        return nil
    }

    private func loadStoryPNG(id: UUID, fileName: String) -> Image? {
        let url = StoryFileStore(rootURL: documentsURL).storyDirectory(id: id).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return uiImage(from: data)
    }
}

import ImageGenKit
import PhotosUI
import PhotoDescribeKit
import StoryPromptKit
import SwiftUI
import VovoUI

#if canImport(UIKit)
import UIKit
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
    @State private var pipelineTask: Task<Void, Never>?
    @State private var phase: PipelinePhase = .story
    @FocusState private var seedFocused: Bool

    public init() {}

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
                if pages.isEmpty {
                    createFlow
                } else {
                    reader
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
            }
        }
    }

    private var runningLabel: String {
        switch phase {
        case .caption, .story:
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
                            pageImage(page)
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
        }
    }

    @ViewBuilder
    private func pageImage(_ page: StoryPage) -> some View {
        if let name = page.imageFileName,
           let img = loadStoryPNG(id: storyID, fileName: name) {
            img
                .resizable()
                .scaledToFit()
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

    @MainActor
    private func startPipeline() async {
        errorMessage = nil
        isRunning = true
        phase = .story
        setIdleTimer(true)
        let id = UUID()
        storyID = id
        pages = []
        title = ""
        summary = ""
        let photo: PhotoDescribeInput? = photoData.map { PhotoDescribeInput(imageData: $0) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let pipeline = SeedPipeline(
            storyGenerator: DeviceStoryGenerator(modelStore: storyStore),
            illustrationPrompts: DeviceIllustrationPromptGenerator(
                completer: DevicePromptCompleter(modelStore: storyStore),
                language: lang
            ),
            imageGenerator: DeviceImageGenerator(packStore: imageStore),
            photoDescriber: DevicePhotoDescriber(modelStore: storyStore),
            memory: MemorySequencer(),
            store: StoryFileStore(rootURL: docs)
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
        case .illustrationReady(let index, let fileName):
            if let i = pages.firstIndex(where: { $0.index == index }) {
                pages[i].imageFileName = fileName
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
            if pages.isEmpty { isRunning = false }
        case .finished:
            break
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
        #endif
        return nil
    }

    private func loadStoryPNG(id: UUID, fileName: String) -> Image? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = StoryFileStore(rootURL: docs).storyDirectory(id: id).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return uiImage(from: data)
    }
}

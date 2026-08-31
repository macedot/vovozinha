import PhotosUI
import SwiftUI
import VovoUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

/// Whether the on-device Core ML image pack is available for img2img.
enum ImagePackGateState: Equatable {
    case checking
    case ready
    case needsModel
    case downloading(ModelDownloadProgress)
    case importing
    case failed(message: String)
    case halted
}

/// UI surface for on-device anime img2img (DEBUG harness).
///
/// Reuses the VovoUI chrome + the shared model-gate L10n keys (same pack concept as the
/// story/VLM gate). Dev controls (strength / steps / CFG / scheduler / seed / bucket) use
/// English labels — this is a DEBUG harness, not shipping UI.
public struct ImageGenFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore

    @State private var generator: any ImageGenerating
    @State private var packStore: CoreMLImagePackStore
    @State private var gate: ImagePackGateState = .checking
    @State private var showFileImporter = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isGenerating = false
    @State private var result: ImageGenResult?
    @State private var errorMessage: String?

    // Dev controls (DEBUG only).
    @State private var prompt: String = ""
    @State private var negativePrompt: String = ""
    @State private var strength: Double = 0.6
    @State private var stepCount: Double = 25
    @State private var guidance: Double = 6.0
    @State private var scheduler: ImageGenScheduler = .dpmSolverMultistep
    @State private var seedRandom = true
    @State private var seed: Double = 0
    @State private var bucket: ImageGenBucket = .square
    @State private var mode: ImageGenMode = .imageToImage

    public init(
        generator: (any ImageGenerating)? = nil,
        packStore: CoreMLImagePackStore = CoreMLImagePackStore()
    ) {
        let store = packStore
        _packStore = State(initialValue: store)
        _generator = State(initialValue: generator ?? DeviceImageGenerator(packStore: store))
    }

    private var lang: AppLanguage { languageStore.language }

    private var canGenerate: Bool {
        !isGenerating && (mode == .textToImage || selectedImageData != nil)
    }

    public var body: some View {
        VStack(spacing: 0) {
            LanguageBar()

            switch gate {
            case .checking:               gateChecking
            case .ready:                  generateFlow
            case .needsModel:             gateNeedsModel
            case .downloading(let snap):  gateDownloading(snap)
            case .importing:              gateImporting
            case .failed(let message):    gateFailed(message: message)
            case .halted:                 gateHalted
            }
        }
        .task { await refreshGate() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImportResult(result) }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPickerItem(newItem) }
        }
    }

    // MARK: - Pack gate (reuse story L10n — same pack concept)

    private var gateChecking: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateChecking, lang),
            scrolls: false
        ) {
            ProgressView().tint(VovoTheme.amber).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gateNeedsModel: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateBody, lang),
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Button { Task { await startDownload() } } label: {
                    Text(VovoL10n.t(.storyModelGateDownload, lang))
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: true))

                Button { showFileImporter = true } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())

                Button { Task { await startDownload() }; gate = .halted } label: {
                    Text(VovoL10n.t(.storyModelGateNotNow, lang))
                }
                .buttonStyle(VovoSecondaryButtonStyle())
            }
        }
    }

    private func gateDownloading(_ snap: ModelDownloadProgress) -> some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: downloadPhaseSubtitle(snap),
            scrolls: false
        ) {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                if snap.bytesTotal != nil || snap.fraction > 0 {
                    ProgressView(value: max(snap.fraction, 0.02)) {
                        Text("\(Int(snap.fraction * 100))% · \(snap.formattedSpeed)/s · ETA \(snap.formattedETA ?? "—")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VovoTheme.cream.opacity(0.85))
                    }
                    .tint(VovoTheme.amber)
                    .id(snap.bytesReceived)
                } else {
                    ProgressView().tint(VovoTheme.amber)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func downloadPhaseSubtitle(_ snap: ModelDownloadProgress) -> String {
        switch snap.phase {
        case .downloading: return VovoL10n.t(.storyModelGateDownloading, lang)
        case .verifying:   return VovoL10n.t(.storyModelGateVerifying, lang)
        case .unpacking:   return VovoL10n.t(.storyModelGateUnpacking, lang)
        case .finished:    return VovoL10n.t(.storyModelGateDownloading, lang)
        }
    }

    private var gateImporting: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateImporting, lang),
            scrolls: false
        ) {
            ProgressView().tint(VovoTheme.amber).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gateFailed(message: String) -> some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: message,
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Button { Task { await startDownload() } } label: {
                    Text(VovoL10n.t(.storyModelGateRetry, lang))
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: true))

                Button { showFileImporter = true } label: {
                    Text(VovoL10n.t(.storyModelGateImport, lang))
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
            Button { Task { await startDownload() } } label: {
                Text(VovoL10n.t(.storyModelGateDownload, lang))
            }
            .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
        }
    }

    // MARK: - Generate flow

    private var generateFlow: some View {
        VovoScreen(title: "Image gen", subtitle: "On-device anime (DEBUG)", scrolls: true) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Mode", selection: $mode) {
                    Text("img2img").tag(ImageGenMode.imageToImage)
                    Text("txt2img").tag(ImageGenMode.textToImage)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("img2imgMode")

                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Text("Pick photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("img2imgPick")
                .opacity(mode == .imageToImage ? 1 : 0.45)

                if let selectedImageData, let image = platformImage(from: selectedImageData) {
                    image.resizable().scaledToFit().frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("img2imgPreview")
                }

                promptField("Prompt", text: $prompt, id: "img2imgPrompt")
                promptField("Negative (blank = locked kids default)", text: $negativePrompt, id: "img2imgNegative")

                devControls

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(VovoTheme.softPink)
                }

                Button { Task { await generateSelected() } } label: {
                    if isGenerating {
                        HStack {
                            ProgressView().tint(VovoTheme.deepNight)
                            Text("Generating…").foregroundStyle(VovoTheme.deepNight)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else {
                        Text("Generate")
                    }
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: canGenerate))
                .disabled(!canGenerate)
                .accessibilityIdentifier("img2imgGenerate")

                if let result {
                    VStack(alignment: .leading, spacing: 8) {
                        platformImage(cgImage: result.cgImage)?
                            .resizable().scaledToFit().frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("img2imgResult")
                        Text("seed \(result.seed) · \(String(format: "%.1f", result.elapsedSeconds))s · \(result.bucket.rawValue)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VovoTheme.cream.opacity(0.75))

                        #if canImport(UIKit)
                        Button { saveResult(result.cgImage) } label: { Text("Save to Photos") }
                            .buttonStyle(VovoSecondaryButtonStyle())
                        if let shareURL = shareablePNG(from: result.cgImage) {
                            ShareLink(
                                item: shareURL,
                                preview: SharePreview("Img2Img result", image: Image(uiImage: UIImage(cgImage: result.cgImage)))
                            ) {
                                Text("Share").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(VovoSecondaryButtonStyle())
                        }
                        #endif
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func promptField(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(VovoTheme.cream.opacity(0.75))
            TextField(label, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .accessibilityIdentifier(id)
        }
    }

    private var devControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow("Strength", value: $strength, range: 0.1...0.9, step: 0.05, fmt: "%.2f")
            sliderRow("Steps", value: $stepCount, range: 10...40, step: 1, fmt: "%.0f")
            sliderRow("CFG", value: $guidance, range: 1...12, step: 0.5, fmt: "%.1f")

            Picker("Sampler", selection: $scheduler) {
                ForEach(ImageGenScheduler.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Bucket", selection: $bucket) {
                ForEach(ImageGenBucket.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Random seed", isOn: $seedRandom)
            if !seedRandom {
                sliderRow("Seed", value: $seed, range: 0...Double(UInt32.max), step: 1, fmt: "%.0f")
            }
        }
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(VovoTheme.cream.opacity(0.75))
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.caption.monospacedDigit()).foregroundStyle(VovoTheme.amber)
            }
            Slider(value: value, in: range, step: step).tint(VovoTheme.amber)
        }
    }

    @ViewBuilder
    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) { Image(nsImage: ns) }
        #endif
    }

    @ViewBuilder
    private func platformImage(cgImage: CGImage) -> Image? {
        #if canImport(UIKit)
        Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        #endif
    }

    // MARK: - Actions

    @MainActor
    private func refreshGate() async {
        gate = .checking
        gate = await packStore.isPackPresent() ? .ready : .needsModel
    }

    @MainActor
    private func startDownload() async {
        gate = .downloading(.zero)
        do {
            try await packStore.download { snapshot in gate = .downloading(snapshot) }
            gate = await packStore.isPackPresent() ? .ready : .failed(message: "Download finished but pack is incomplete.")
        } catch {
            let msg = error.localizedDescription
            gate = .failed(message: msg.isEmpty ? "Download failed." : msg)
        }
    }

    @MainActor
    private func handleImportResult(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure: return
        case .success(let urls):
            guard let url = urls.first else { return }
            gate = .importing
            do {
                try await packStore.importPack(from: url)
                gate = await packStore.isPackPresent() ? .ready : .failed(message: "Import finished but pack is incomplete.")
            } catch {
                gate = .failed(message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func loadPickerItem(_ item: PhotosPickerItem?) async {
        result = nil
        errorMessage = nil
        guard let item else { selectedImageData = nil; return }
        do {
            if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
                selectedImageData = data
            } else {
                selectedImageData = nil
                errorMessage = "Could not read that photo."
            }
        } catch {
            selectedImageData = nil
            errorMessage = "Could not read that photo."
        }
    }

    @MainActor
    private func generateSelected() async {
        if mode == .imageToImage, selectedImageData == nil { return }
        errorMessage = nil
        result = nil
        isGenerating = true
        defer { isGenerating = false }

        let config = ImageGenConfig(
            strength: Float(strength),
            stepCount: Int(stepCount),
            guidanceScale: Float(guidance),
            scheduler: scheduler,
            seed: seedRandom ? nil : UInt32(clamping: Int64(seed)),
            bucket: bucket,
            mode: mode,
            prompt: prompt,
            negativePrompt: negativePrompt
        )

        let input = ImageGenInput(imageData: selectedImageData ?? Data())
        do {
            result = try await generator.generate(input, config: config)
        } catch let e as ImageGenError {
            switch e {
            case .packNotInstalled:   errorMessage = "Pack not installed."; gate = .needsModel
            case .vaeEncoderMissing:  errorMessage = "Installed pack has no VAE encoder (img2img needs one)."
            case .invalidImage:       errorMessage = "That photo could not be used."
            case .generationFailed:   errorMessage = "Generation failed."
            }
        } catch {
            errorMessage = "Generation failed."
        }
    }

    #if canImport(UIKit)
    @MainActor
    private func saveResult(_ cgImage: CGImage) {
        UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), nil, nil, nil)
    }

    /// Renders the result to a temporary PNG and returns a file URL for `ShareLink`.
    private func shareablePNG(from cgImage: CGImage) -> URL? {
        let ui = UIImage(cgImage: cgImage)
        guard let png = ui.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("img2img-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(AppKit)
import AppKit
typealias NSSize = AppKit.NSSize
#endif

#Preview {
    ImageGenFeatureView()
        .environment(LanguageStore(preferenceRaw: AppLanguage.englishUS.rawValue))
}

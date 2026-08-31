import PhotosUI
import SwiftUI
import StoryPromptKit
import VovoUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

/// Whether the on-device VLM pack is available for photo describe.
enum PhotoModelGateState: Equatable {
    case checking
    case ready
    case needsModel
    case downloading(ModelDownloadProgress)
    case importing
    case failed(message: String)
    case halted
}

/// UI surface for Photo Describe (DEBUG harness). Same Qwen pack as Story Prompt; VLM path for captions.
public struct PhotoDescribeFeatureView: View {
    @Environment(LanguageStore.self) private var languageStore

    @State private var describer: any PhotoDescribing
    @State private var modelStore: OnDeviceMLXModelStore
    @State private var modelGate: PhotoModelGateState = .checking
    @State private var showFileImporter = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isDescribing = false
    @State private var caption: PhotoCaption?
    @State private var errorMessage: String?

    public init(
        describer: (any PhotoDescribing)? = nil,
        modelStore: OnDeviceMLXModelStore = OnDeviceMLXModelStore()
    ) {
        let store = modelStore
        _modelStore = State(initialValue: store)
        _describer = State(initialValue: describer ?? DevicePhotoDescriber(modelStore: store))
    }

    private var lang: AppLanguage { languageStore.language }

    private var canDescribe: Bool {
        selectedImageData != nil && !isDescribing
    }

    public var body: some View {
        VStack(spacing: 0) {
            LanguageBar()

            switch modelGate {
            case .checking:
                gateChecking
            case .ready:
                describeFlow
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
        .onChange(of: languageStore.language) { _, _ in
            caption = nil
            errorMessage = nil
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPickerItem(newItem) }
        }
    }

    // MARK: - Model gate (reuse story L10n — same pack)

    private var gateChecking: some View {
        VovoScreen(
            title: VovoL10n.t(.storyModelGateTitle, lang),
            subtitle: VovoL10n.t(.storyModelGateChecking, lang),
            scrolls: false
        ) {
            ProgressView()
                .tint(VovoTheme.amber)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .id(snapshot.bytesReceived)
                } else {
                    ProgressView()
                        .tint(VovoTheme.amber)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func downloadPhaseSubtitle(_ snapshot: ModelDownloadProgress) -> String {
        switch snapshot.phase {
        case .downloading: return VovoL10n.t(.storyModelGateDownloading, lang)
        case .verifying: return VovoL10n.t(.storyModelGateVerifying, lang)
        case .unpacking: return VovoL10n.t(.storyModelGateUnpacking, lang)
        case .finished: return VovoL10n.t(.storyModelGateDownloading, lang)
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

                Button {
                    showFileImporter = true
                } label: {
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
            Button {
                Task { await startModelDownload() }
            } label: {
                Text(VovoL10n.t(.storyModelGateDownload, lang))
            }
            .buttonStyle(VovoPrimaryButtonStyle(enabled: true))
        }
    }

    // MARK: - Describe flow

    private var describeFlow: some View {
        VovoScreen(
            title: VovoL10n.t(.photoDescribeTitle, lang),
            subtitle: VovoL10n.t(.photoDescribeSubtitle, lang),
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text(VovoL10n.t(.photoDescribePick, lang))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VovoSecondaryButtonStyle())
                .accessibilityIdentifier("photoDescribePick")

                if let selectedImageData, let image = platformImage(from: selectedImageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("photoDescribePreview")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(VovoTheme.softPink)
                }

                Button {
                    Task { await describeSelected() }
                } label: {
                    if isDescribing {
                        ProgressView()
                            .tint(VovoTheme.deepNight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    } else {
                        Text(VovoL10n.t(.photoDescribeAction, lang))
                    }
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: canDescribe))
                .disabled(!canDescribe)
                .accessibilityIdentifier("photoDescribeAction")

                if let caption {
                    Text(caption.text)
                        .font(.body)
                        .foregroundStyle(VovoTheme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(VovoTheme.cardFill)
                        )
                        .accessibilityIdentifier("photoDescribeResult")
                }
            }
        }
    }

    @ViewBuilder
    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) {
            return Image(nsImage: ns)
        }
        #endif
        return nil
    }

    // MARK: - Actions

    @MainActor
    private func refreshModelGate() async {
        modelGate = .checking
        if await modelStore.isModelPresent() {
            modelGate = .ready
            return
        }
        modelGate = .needsModel
    }

    @MainActor
    private func startModelDownload() async {
        modelGate = .downloading(.zero)
        do {
            try await modelStore.download { snapshot in
                modelGate = .downloading(snapshot)
            }
            modelGate = await modelStore.isModelPresent()
                ? .ready
                : .failed(message: VovoL10n.t(.photoDescribeFailed, lang))
        } catch {
            let msg = error.localizedDescription
            modelGate = .failed(
                message: msg.isEmpty ? VovoL10n.t(.photoDescribeFailed, lang) : msg
            )
        }
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
                    : .failed(message: OnDeviceMLXModelStore.ImportError.copyFailed.localizedDescription)
            } catch {
                let msg = error.localizedDescription
                modelGate = .failed(
                    message: msg.isEmpty ? VovoL10n.t(.photoDescribeFailed, lang) : msg
                )
            }
        }
    }

    @MainActor
    private func loadPickerItem(_ item: PhotosPickerItem?) async {
        caption = nil
        errorMessage = nil
        guard let item else {
            selectedImageData = nil
            return
        }
        do {
            if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
                selectedImageData = data
            } else {
                selectedImageData = nil
                errorMessage = VovoL10n.t(.photoDescribeInvalidImage, lang)
            }
        } catch {
            selectedImageData = nil
            errorMessage = VovoL10n.t(.photoDescribeInvalidImage, lang)
        }
    }

    @MainActor
    private func describeSelected() async {
        guard let selectedImageData else { return }
        errorMessage = nil
        caption = nil
        isDescribing = true
        defer { isDescribing = false }

        let input = PhotoDescribeInput(imageData: selectedImageData)
        do {
            caption = try await describer.describe(input, language: lang)
        } catch let e as PhotoDescribeError {
            switch e {
            case .modelNotInstalled:
                errorMessage = VovoL10n.t(.storyModelNotInstalled, lang)
                modelGate = .needsModel
            case .invalidImage:
                errorMessage = VovoL10n.t(.photoDescribeInvalidImage, lang)
            case .describeFailed:
                errorMessage = VovoL10n.t(.photoDescribeFailed, lang)
            }
        } catch {
            errorMessage = VovoL10n.t(.photoDescribeFailed, lang)
        }
    }
}

#Preview {
    PhotoDescribeFeatureView()
        .environment(LanguageStore(preferenceRaw: AppLanguage.englishUS.rawValue))
}

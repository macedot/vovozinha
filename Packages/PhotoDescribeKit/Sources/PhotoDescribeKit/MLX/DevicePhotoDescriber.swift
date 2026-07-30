import Foundation
import StoryPromptKit
import VovoUI

/// Production describer: **Qwen3.5 MLX VLM only**. No fabricated captions.
///
/// - Model missing → `PhotoDescribeError.modelNotInstalled`
/// - Inference or empty caption → `PhotoDescribeError.describeFailed`
public struct DevicePhotoDescriber: PhotoDescribing {
    private let modelStore: OnDeviceMLXModelStore
    private let sessionProvider: @Sendable (URL) throws -> any MLXPhotoDescribeSessioning

    public init(modelStore: OnDeviceMLXModelStore = OnDeviceMLXModelStore()) {
        self.init(modelStore: modelStore, sessionProvider: DevicePhotoDescriber.defaultSessionProvider)
    }

    init(
        modelStore: OnDeviceMLXModelStore,
        sessionProvider: @escaping @Sendable (URL) throws -> any MLXPhotoDescribeSessioning
    ) {
        self.modelStore = modelStore
        self.sessionProvider = sessionProvider
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
    static let defaultSessionProvider: @Sendable (URL) throws -> any MLXPhotoDescribeSessioning = { dir in
        MLXPhotoDescribeSession(modelDirectory: dir)
    }
    #else
    static let defaultSessionProvider: @Sendable (URL) throws -> any MLXPhotoDescribeSessioning = { _ in
        throw PhotoDescribeError.describeFailed
    }
    #endif

    public func describe(_ image: PhotoDescribeInput, language: AppLanguage) async throws -> PhotoCaption {
        guard !image.isEmpty else {
            throw PhotoDescribeError.invalidImage
        }

        guard await modelStore.isModelPresent() else {
            throw PhotoDescribeError.modelNotInstalled
        }

        let modelDir = await modelStore.modelDirectory()
        let session = try sessionProvider(modelDir)
        let describer = MLXPhotoDescriber(session: session)
        return try await describer.describe(image, language: language)
    }
}

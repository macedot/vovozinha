import Foundation
import VovoUI

/// Production generator: **Qwen3.5 MLX only**. No static / template story body.
///
/// - Model missing → `StoryPromptError.modelNotInstalled`
/// - Inference or parse failure → `StoryPromptError.generationFailed` (or underlying error)
/// - Never invents paragraphs without the model.
public struct DeviceStoryGenerator: StoryFromPromptGenerating {
    private let modelStore: OnDeviceMLXModelStore
    private let sessionProvider: @Sendable (URL) throws -> any MLXStoryEngineSessioning

    public init(modelStore: OnDeviceMLXModelStore = OnDeviceMLXModelStore()) {
        self.init(modelStore: modelStore, sessionProvider: DeviceStoryGenerator.defaultSessionProvider)
    }

    init(
        modelStore: OnDeviceMLXModelStore,
        sessionProvider: @escaping @Sendable (URL) throws -> any MLXStoryEngineSessioning
    ) {
        self.modelStore = modelStore
        self.sessionProvider = sessionProvider
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    static let defaultSessionProvider: @Sendable (URL) throws -> any MLXStoryEngineSessioning = { dir in
        MLXStoryEngineSession(modelDirectory: dir)
    }
    #else
    static let defaultSessionProvider: @Sendable (URL) throws -> any MLXStoryEngineSessioning = { _ in
        throw StoryPromptError.generationFailed
    }
    #endif

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()

        guard await modelStore.isModelPresent() else {
            throw StoryPromptError.modelNotInstalled
        }

        let modelDir = await modelStore.modelDirectory()
        let session = try sessionProvider(modelDir)
        let generator = try MLXStoryGenerator(modelDirectory: modelDir, session: session)
        var lastError: Error = StoryPromptError.generationFailed
        for _ in 0..<2 {
            do {
                return try await generator.generate(from: prompt)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

import Foundation

/// Raw on-device LLM completion using the Qwen story pack. No fabrication.
public struct DevicePromptCompleter: Sendable {
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

    public func complete(_ prompt: String) async throws -> String {
        guard await modelStore.isModelPresent() else {
            throw StoryPromptError.modelNotInstalled
        }
        let modelDir = await modelStore.modelDirectory()
        let session = try sessionProvider(modelDir)
        let raw: String
        do {
            raw = try await session.send(prompt)
        } catch {
            throw StoryPromptError.generationFailed
        }
        let cleaned = MLXStoryGenerator.stripThinkingBlocks(raw)
        guard !cleaned.isEmpty else { throw StoryPromptError.generationFailed }
        return cleaned
    }
}

import Foundation
import CoreImage
import CoreGraphics

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

/// Concrete MLX VLM adapter for **Qwen3.5-4B-MLX-4bit** (keeps vision weights).
final class MLXPhotoDescribeSession: MLXPhotoDescribeSessioning, @unchecked Sendable {
    private let modelDirectory: URL

    static let defaultMaxTokens = 320
    static let defaultTemperature: Float = 0.4
    static let defaultTopP: Float = 0.9
    static let defaultTopK = 20

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func send(prompt: String, image: CIImage) async throws -> String {
        defer { MLX.Memory.clearCache() }
        return try await Task.detached(priority: .userInitiated) { [modelDirectory] in
            let container = try await Self.loadContainer(from: modelDirectory)
            let parameters = GenerateParameters(
                maxTokens: Self.defaultMaxTokens,
                temperature: Self.defaultTemperature,
                topP: Self.defaultTopP,
                topK: Self.defaultTopK
            )
            let instructions = """
            You describe photos briefly for parents. Answer with the caption only. \
            Do not include chain-of-thought, analysis, or tool calls.
            """
            let session = ChatSession(
                container,
                instructions: instructions,
                generateParameters: parameters,
                processing: .init(resize: CGSize(width: 512, height: 512)),
                additionalContext: ["enable_thinking": false]
            )
            let text = try await session.respond(
                to: prompt,
                image: .ciImage(image)
            )
            #if DEBUG
            print(
                "[MLXPhoto] raw reply chars=\(text.count) preview=\(text.prefix(240).replacingOccurrences(of: "\n", with: "⏎"))"
            )
            #endif
            return text
        }.value
    }

    private static func loadContainer(from directory: URL) async throws -> ModelContainer {
        // Vision path: load through VLM so vision_tower stays available.
        try await VLMModelFactory.shared.loadContainer(
            from: directory,
            using: HuggingFaceTokenizerLoader()
        )
    }
}
#endif

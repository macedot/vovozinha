import Foundation
import CoreImage
import StoryPromptKit
import VovoUI

/// On-device VLM captioner for a local photo.
public struct MLXPhotoDescriber: PhotoDescribing {
    private let session: any MLXPhotoDescribeSessioning

    public init(session: any MLXPhotoDescribeSessioning) {
        self.session = session
    }

    public func describe(_ image: PhotoDescribeInput, language: AppLanguage) async throws -> PhotoCaption {
        guard let ciImage = image.makeCIImage() else {
            throw PhotoDescribeError.invalidImage
        }

        let prompt = PhotoDescribeTemplate.filledDescribePrompt(language: language)
        guard !prompt.isEmpty else {
            throw PhotoDescribeError.describeFailed
        }

        let raw: String
        do {
            raw = try await session.send(prompt: prompt, image: ciImage)
        } catch {
            #if DEBUG
            print("[MLXPhoto] session.send failed: \(error)")
            #endif
            throw PhotoDescribeError.describeFailed
        }

        let cleaned = Self.normalizeCaption(MLXStoryGenerator.stripThinkingBlocks(raw))
        guard !cleaned.isEmpty else {
            throw PhotoDescribeError.describeFailed
        }

        return PhotoCaption(text: cleaned, language: language)
    }

    /// Drop Qwen-style thinking wrappers (reuses canonical StoryPromptKit implementation).
    static func stripThinkingBlocks(_ raw: String) -> String {
        MLXStoryGenerator.stripThinkingBlocks(raw)
    }

    static func normalizeCaption(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

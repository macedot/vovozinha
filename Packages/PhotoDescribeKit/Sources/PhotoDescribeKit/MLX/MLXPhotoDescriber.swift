import Foundation
import CoreImage
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

        let cleaned = Self.normalizeCaption(Self.stripThinkingBlocks(raw))
        guard !cleaned.isEmpty else {
            throw PhotoDescribeError.describeFailed
        }

        return PhotoCaption(text: cleaned, language: language)
    }

    /// Drop Qwen-style thinking wrappers if the model emits them despite `enable_thinking: false`.
    static func stripThinkingBlocks(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(
            pattern: #"(?is)<think>.*?</think>"#,
            options: []
        ) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        if let open = text.range(of: "<think>", options: .caseInsensitive) {
            if let close = text.range(of: "</think>", options: [.caseInsensitive, .backwards]),
               close.lowerBound > open.lowerBound
            {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                text = String(text[text.startIndex..<open.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

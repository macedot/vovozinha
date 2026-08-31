import Foundation

/// On-device anime image generation (Core ML Stable Diffusion).
///
/// Depends on `VovoUI`, a local `ml-stable-diffusion` 1.1.1 checkout (vendored CLIP
/// tokenizer — no swift-transformers pin), and `ZIPFoundation`. Safe to link next to
/// StoryPromptKit in the host app.
public enum ImageGenKit {
    /// Sentinel for the package's canonical on-disk pack directory name.
    public static let packDirectoryName = "ImagePack"
}

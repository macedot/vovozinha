import Foundation

/// Target resolution bucket. The source photo is resized toward the nearest bucket
/// (by aspect ratio) before VAE encoding.
///
/// `pixels` is resolved through a `modelSize` so the **same buckets** serve SD1.5 (512)
/// now and SDXL (1024) later without code changes — only the model-size flag flips.
public enum ImageGenBucket: String, Sendable, CaseIterable, Identifiable {
    case square
    case portrait
    case landscape

    public var id: String { rawValue }

    /// Pixel dimensions for this bucket at the given model size.
    public func pixels(modelSize: ImageGenModelSize) -> (width: Int, height: Int) {
        let s = modelSize.side
        switch self {
        case .square:    return (s, s)
        case .portrait:  return (s, Int((Float(s) * 1.5).rounded()))   // 512×768 | 832×1248
        case .landscape: return (Int((Float(s) * 1.5).rounded()), s)   // 768×512 | 1248×832
        }
    }

    /// Selects the bucket whose aspect ratio is closest to `width/height`.
    public static func nearest(toWidth width: Int, height: Int) -> ImageGenBucket {
        guard width > 0, height > 0 else { return .square }
        let aspect = Float(width) / Float(height)
        if aspect > 1.15 { return .landscape }
        if aspect < 0.87 { return .portrait }
        return .square
    }
}

/// Native generation side length of the backing model. SD1.5 = 512; SDXL = 1024.
public enum ImageGenModelSize: Int, Sendable {
    case sd15 = 512
    case sdxl = 1024

    public var side: Int { rawValue }
}

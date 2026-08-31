import Foundation
import CoreGraphics
import CoreImage
import ImageIO

/// Pure image-resize logic for img2img: picks the nearest bucket, enforces a minimum
/// side (the model's native size), caps the maximum input side to bound memory, and
/// preserves aspect ratio.
///
/// All functions are free of side effects and safe to unit-test on macOS.
public enum ImageResizer {

    /// Hard cap on the longest input side before any work happens. Source photos above
    /// this are pre-downscaled so VAE encode peak memory stays bounded.
    public static let maxInputSide: Int = 2048

    /// Resizes `source` into the nearest bucket for `modelSize`, enforcing the bucket's
    /// exact pixel dimensions. Returns nil if the source is empty.
    ///
    /// The chosen bucket is the one whose aspect ratio is closest to the source; the
    /// image is then scaled to fill that bucket exactly (minor aspect distortion is
    /// acceptable — the diffusion model expects fixed bucket dimensions).
    public static func resize(
        _ source: CGImage,
        toBucket bucket: ImageGenBucket? = nil,
        modelSize: ImageGenModelSize = .sd15
    ) -> (cgImage: CGImage, bucket: ImageGenBucket)? {
        let srcW = source.width
        let srcH = source.height
        guard srcW > 0, srcH > 0 else { return nil }

        // Pre-downscale if the source is huge, to bound memory. This pass targets a
        // longest side of `maxInputSide`, preserving aspect.
        var working = source
        let longest = max(srcW, srcH)
        if longest > maxInputSide {
            let scale = Float(maxInputSide) / Float(longest)
            let newW = max(1, Int(Float(srcW) * scale))
            let newH = max(1, Int(Float(srcH) * scale))
            guard let capped = redraw(source, width: newW, height: newH) else { return nil }
            working = capped
        }

        // Resolve the target bucket (explicit, or nearest by aspect of the *original*).
        let chosen = bucket ?? .nearest(toWidth: srcW, height: srcH)
        let target = chosen.pixels(modelSize: modelSize)

        guard let resized = redraw(working, width: target.width, height: target.height) else {
            return nil
        }
        return (resized, chosen)
    }

    /// Redraws `image` to `width`×`height` using a high-quality `CGContext`.
    static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

/// Source photo bytes for on-device img2img. Never uploaded.
public struct ImageGenInput: Sendable {
    public let imageData: Data

    public init(imageData: Data) {
        self.imageData = imageData
    }

    public var isEmpty: Bool { imageData.isEmpty }

    /// Decodes image data into an upright `CGImage`. Returns nil if undecodable.
    /// Applies EXIF orientation (iPhone camera HEICs are often `.right`).
    public func makeCGImage() -> CGImage? {
        guard !imageData.isEmpty else { return nil }
        #if canImport(UIKit)
        if let ui = UIImage(data: imageData) {
            return Self.uprightCGImage(from: ui)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: imageData),
           let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            return cg
        }
        #endif
        if let ci = CIImage(data: imageData) {
            let oriented = ci.oriented(forExifOrientation: Self.exifOrientation(of: ci))
            let context = CIContext(options: [.useSoftwareRenderer: false])
            return context.createCGImage(oriented, from: oriented.extent)
        }
        return nil
    }

    #if canImport(UIKit)
    /// `UIImage.cgImage` ignores `imageOrientation`. Draw to apply it.
    private static func uprightCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return drawn.cgImage
    }
    #endif

    private static func exifOrientation(of ci: CIImage) -> Int32 {
        if let value = ci.properties[kCGImagePropertyOrientation as String] as? Int32 {
            return value
        }
        return 1
    }
}

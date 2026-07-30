import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

/// Local image bytes for on-device VLM describe. Never uploaded.
public struct PhotoDescribeInput: Sendable {
    public let imageData: Data

    public init(imageData: Data) {
        self.imageData = imageData
    }

    public var isEmpty: Bool { imageData.isEmpty }

    /// Decodes image data for the VLM session. Returns nil if undecodable.
    public func makeCIImage() -> CIImage? {
        guard !imageData.isEmpty else { return nil }
        if let ci = CIImage(data: imageData) {
            return ci
        }
        #if canImport(UIKit)
        if let ui = UIImage(data: imageData), let cg = ui.cgImage {
            return CIImage(cgImage: cg)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: imageData),
           let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            return CIImage(cgImage: cg)
        }
        #endif
        return nil
    }
}

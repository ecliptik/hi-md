import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension PlatformImage {
    /// Returns a copy scaled down so neither dimension exceeds maxDimension.
    /// Returns self unchanged if already within bounds.
    nonisolated func resized(maxDimension: CGFloat) -> PlatformImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
        #else
        guard let cgImage,
              let context = CGContext(
                  data: nil, width: Int(newSize.width), height: Int(newSize.height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return self }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
        guard let scaled = context.makeImage() else { return self }
        return NSImage(cgImage: scaled, size: newSize)
        #endif
    }

    nonisolated func jpgData(quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        return jpegData(compressionQuality: quality)
        #else
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }
}

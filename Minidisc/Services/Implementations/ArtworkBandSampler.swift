import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

actor ArtworkBandSampler {
    private let context = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func sample(_ image: PlatformImage) -> [Int]? {
        guard !Task.isCancelled, image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 200 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(4, image.size.height * scale))
        guard let cgImage = thumbnail(of: image, size: size) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        let height = extent.height / 4
        var result: [Int] = []
        for index in 0..<4 {
            guard !Task.isCancelled else { return nil }
            let filter = CIFilter.areaAverage()
            filter.inputImage = input
            // Core Image starts at the bottom left; return bands in visual top-to-bottom order.
            filter.extent = CGRect(x: extent.minX, y: extent.maxY - CGFloat(index + 1) * height,
                                   width: extent.width, height: height)
            guard let output = filter.outputImage else { return nil }
            var bytes = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &bytes, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: colorSpace)
            result.append(Int(bytes[0]) << 16 | Int(bytes[1]) << 8 | Int(bytes[2]))
        }
        return result
    }

    /// The image drawn opaque on black at `size`, one pixel per point.
    private func thumbnail(of image: PlatformImage, size: CGSize) -> CGImage? {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.black.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            // Drawing the UIImage also applies its EXIF orientation.
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.cgImage
        #else
        let rect = CGRect(origin: .zero, size: CGSize(width: size.width.rounded(), height: size.height.rounded()))
        guard let source = image.cgImage,
              let bitmap = CGContext(
                  data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8,
                  bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        bitmap.setFillColor(CGColor(gray: 0, alpha: 1))
        bitmap.fill(rect)
        bitmap.draw(source, in: rect)
        return bitmap.makeImage()
        #endif
    }
}

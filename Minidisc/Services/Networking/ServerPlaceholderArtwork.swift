import CoreGraphics
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Navidrome answers a cover request for an album or artist without artwork with its own stand-in
/// image instead of an error: a blue vinyl record for albums, a white star on grey for artists.
/// Recognising them lets the app show its own placeholder. They're matched by their look rather than
/// their bytes, because the server resizes and re-encodes them for each request.
nonisolated enum ServerPlaceholderArtwork {
    static func matches(_ image: PlatformImage) -> Bool {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return false }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        #endif
        return matches(cgImage)
    }

    /// Checks encoded image bytes, decoding only a small thumbnail.
    static func matches(imageData data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary)
        else { return false }
        return matches(image)
    }

    static func matches(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0, abs(width - height) <= max(width, height) / 20,
              let pixels = Self.samples(of: image) else { return false }
        return isAlbumPlaceholder(pixels) || isArtistPlaceholder(pixels)
    }

    // MARK: - Signatures

    private static let side = 32

    /// A ring of saturated blue around a dark grey centre label, with plain corners.
    private static func isAlbumPlaceholder(_ pixels: [Pixel]) -> Bool {
        let ring = pixels.filter { (0.19..<0.35).contains($0.radius) }
        let label = pixels.filter { $0.radius < 0.12 }
        let corners = pixels.filter { $0.radius >= 0.55 }
        let blueRing = Double(ring.count { $0.isRecordBlue }) / Double(ring.count)
        let labelLuma = label.map(\.luma).reduce(0, +) / Double(label.count)
        let labelHasBlue = label.contains { $0.isRecordBlue }
        return blueRing >= 0.9 && labelLuma < 90 && !labelHasBlue && isUniform(corners)
    }

    /// Flat light grey with a white star in the middle and no colour anywhere.
    private static func isArtistPlaceholder(_ pixels: [Pixel]) -> Bool {
        guard pixels.allSatisfy(\.isNeutral) else { return false }
        let centre = pixels.filter { $0.radius < 0.08 }
        let edge = pixels.filter { $0.radius >= 0.45 }
        let centreLuma = centre.map(\.luma).reduce(0, +) / Double(centre.count)
        let edgeLuma = edge.map(\.luma).reduce(0, +) / Double(edge.count)
        return centreLuma > 245 && (222...245).contains(edgeLuma) && isUniform(edge)
    }

    private static func isUniform(_ pixels: [Pixel]) -> Bool {
        let lumas = pixels.map(\.luma)
        let mean = lumas.reduce(0, +) / Double(lumas.count)
        let variance = lumas.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lumas.count)
        return variance.squareRoot() < 12
    }

    // MARK: - Sampling

    private struct Pixel {
        let red: Double, green: Double, blue: Double
        /// Distance from the centre, as a fraction of the side.
        let radius: Double

        var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

        var isNeutral: Bool { max(red, green, blue) - min(red, green, blue) < 8 }

        /// The record's blue: hue around 210–245°, strongly saturated, not dark.
        var isRecordBlue: Bool {
            let maxValue = max(red, green, blue), minValue = min(red, green, blue)
            guard maxValue > 115, maxValue == blue, maxValue - minValue > maxValue * 0.5 else { return false }
            let hue = 240 + 60 * (red - green) / (maxValue - minValue)
            return (195...245).contains(hue)
        }
    }

    /// Draws the image at 32×32 over black (the album stand-in has transparent corners) and reads
    /// the pixels back.
    private static func samples(of image: CGImage) -> [Pixel]? {
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        let centre = Double(side - 1) / 2
        return (0..<(side * side)).map { index in
            let x = index % side, y = index / side, offset = index * 4
            let dx = Double(x) - centre, dy = Double(y) - centre
            return Pixel(
                red: Double(buffer[offset]), green: Double(buffer[offset + 1]), blue: Double(buffer[offset + 2]),
                radius: (dx * dx + dy * dy).squareRoot() / Double(side)
            )
        }
    }
}

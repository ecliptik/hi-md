import CoreGraphics
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A decoded cover, checked against the server's stand-ins where it was decoded, off the MainActor.
nonisolated struct DecodedArtwork: Sendable {
    let image: PlatformImage
    let isServerPlaceholder: Bool

    init(_ image: PlatformImage) {
        self.image = image
        isServerPlaceholder = ServerPlaceholderArtwork.matches(image)
    }

    /// For an image decoded elsewhere, such as by an injected decoder.
    @concurrent
    static func isServerPlaceholder(_ image: PlatformImage) async -> Bool {
        ServerPlaceholderArtwork.matches(image)
    }
}

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

    /// Runs for every cover the app decodes, so it draws into a stack buffer and reads the regions
    /// in one pass, without per-pixel arrays. Callers run it off the MainActor, next to the decode.
    static func matches(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0, abs(width - height) <= max(width, height) / 20 else { return false }
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: side * side * 4) { buffer in
            buffer.initialize(repeating: 0)
            guard draw(image, into: buffer) else { return false }
            let signature = Signature(buffer)
            return signature.isAlbumPlaceholder(buffer) || signature.isArtistPlaceholder(buffer)
        }
    }

    // MARK: - Signatures

    private static let side = 32
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Each sample's distance from the centre, as a fraction of the side.
    private static let radii: [Double] = {
        let centre = Double(side - 1) / 2
        return (0..<(side * side)).map { index in
            let dx = Double(index % side) - centre, dy = Double(index / side) - centre
            return (dx * dx + dy * dy).squareRoot() / Double(side)
        }
    }()

    /// Region sums gathered in one pass over the samples. They're added in sample order, so they
    /// equal the per-region sums the earlier array-based version computed.
    private struct Signature {
        var ringCount = 0, ringBlue = 0
        var labelCount = 0, labelLuma = 0.0, labelHasBlue = false
        var cornerCount = 0, cornerLuma = 0.0
        var centreCount = 0, centreLuma = 0.0
        var edgeCount = 0, edgeLuma = 0.0
        var allNeutral = true

        init(_ buffer: UnsafeMutableBufferPointer<UInt8>) {
            for index in 0..<(side * side) {
                let pixel = Pixel(buffer, index)
                let radius = radii[index]
                let luma = pixel.luma
                if (0.19..<0.35).contains(radius) {
                    ringCount += 1
                    if pixel.isRecordBlue { ringBlue += 1 }
                }
                if radius < 0.12 {
                    labelCount += 1
                    labelLuma += luma
                    if pixel.isRecordBlue { labelHasBlue = true }
                }
                if radius >= 0.55 { cornerCount += 1; cornerLuma += luma }
                if radius < 0.08 { centreCount += 1; centreLuma += luma }
                if radius >= 0.45 { edgeCount += 1; edgeLuma += luma }
                if !pixel.isNeutral { allNeutral = false }
            }
        }

        /// A ring of saturated blue around a dark grey centre label, with plain corners.
        func isAlbumPlaceholder(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> Bool {
            let blueRing = Double(ringBlue) / Double(ringCount)
            return blueRing >= 0.9 && labelLuma / Double(labelCount) < 90 && !labelHasBlue
                && isUniform(buffer, mean: cornerLuma / Double(cornerCount), count: cornerCount) { $0 >= 0.55 }
        }

        /// Flat light grey with a white star in the middle and no colour anywhere.
        func isArtistPlaceholder(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> Bool {
            guard allNeutral else { return false }
            let edgeMean = edgeLuma / Double(edgeCount)
            return centreLuma / Double(centreCount) > 245 && (222...245).contains(edgeMean)
                && isUniform(buffer, mean: edgeMean, count: edgeCount) { $0 >= 0.45 }
        }

        /// The spread of a region's brightness, from a second pass over just that region.
        private func isUniform(_ buffer: UnsafeMutableBufferPointer<UInt8>, mean: Double, count: Int,
                               in region: (Double) -> Bool) -> Bool {
            var squares = 0.0
            for index in 0..<(side * side) where region(radii[index]) {
                let deviation = Pixel(buffer, index).luma - mean
                squares += deviation * deviation
            }
            return (squares / Double(count)).squareRoot() < 12
        }
    }

    // MARK: - Sampling

    private struct Pixel {
        let red: Double, green: Double, blue: Double

        init(_ buffer: UnsafeMutableBufferPointer<UInt8>, _ index: Int) {
            let offset = index * 4
            red = Double(buffer[offset])
            green = Double(buffer[offset + 1])
            blue = Double(buffer[offset + 2])
        }

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

    /// Draws the image at 32×32 over black (the album stand-in has transparent corners) into `buffer`.
    private static func draw(_ image: CGImage, into buffer: UnsafeMutableBufferPointer<UInt8>) -> Bool {
        guard let context = CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
}

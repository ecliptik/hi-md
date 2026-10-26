import UIKit

extension UIImage {
    /// The memory the decoded bitmap holds, for costing in-memory caches. Images without a
    /// CGImage are estimated at four bytes per pixel.
    nonisolated var decodedByteCount: Int {
        if let cgImage { return cgImage.bytesPerRow * cgImage.height }
        return Int(size.width * scale) * Int(size.height * scale) * 4
    }
}

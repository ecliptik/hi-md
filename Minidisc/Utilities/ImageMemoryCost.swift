#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension PlatformImage {
    /// The memory the decoded bitmap holds, for costing in-memory caches. Images without a
    /// CGImage are estimated at four bytes per pixel.
    nonisolated var decodedByteCount: Int {
        if let cgImage { return cgImage.bytesPerRow * cgImage.height }
        #if canImport(UIKit)
        return Int(size.width * scale) * Int(size.height * scale) * 4
        #else
        return Int(size.width) * Int(size.height) * 4
        #endif
    }
}

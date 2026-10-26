#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage

extension NSImage {
    /// UIKit's `cgImage`, so shared code can read the bitmap on both platforms.
    nonisolated var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// UIKit's `init(cgImage:)`: the image keeps the bitmap's pixel size.
    nonisolated convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}
#endif

import SwiftUI

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension ImageRenderer {
    /// The rendered image as a UIImage or NSImage.
    var platformImage: PlatformImage? {
        #if canImport(UIKit)
        uiImage
        #else
        nsImage
        #endif
    }
}

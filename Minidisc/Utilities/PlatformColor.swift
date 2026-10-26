#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

extension PlatformColor {
    /// Red, green, blue and alpha, or nil when the colour can't be expressed in RGB.
    nonisolated var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #else
        // AppKit raises instead of failing for colours outside an RGB space, so convert first.
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        #endif
    }

    /// Hue, saturation, brightness and alpha, or nil when the colour can't be expressed in RGB.
    nonisolated var hsba: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat)? {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return nil }
        return (h, s, b, a)
        #else
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        return (rgb.hueComponent, rgb.saturationComponent, rgb.brightnessComponent, rgb.alphaComponent)
        #endif
    }
}

import SwiftUI

extension Color {
    init(platformColor: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: platformColor)
        #else
        self.init(nsColor: platformColor)
        #endif
    }
}

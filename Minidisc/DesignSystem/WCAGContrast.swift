import Foundation

/// WCAG 2.x relative luminance and contrast ratios for sRGB colours, used to tune and test
/// the palette (accents, Wrapped gradients). Pure maths, so callable from any thread.
nonisolated enum WCAGContrast {
    /// Gamma-encoded sRGB components in 0...1.
    nonisolated struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        }

        static let white = RGB(red: 1, green: 1, blue: 1)
        static let black = RGB(red: 0, green: 0, blue: 0)

        /// Every component multiplied by `factor`, the same as a black overlay at `1 - factor`.
        func scaled(by factor: Double) -> RGB {
            RGB(red: red * factor, green: green * factor, blue: blue * factor)
        }

        /// This colour at `opacity` over `background`, composited in gamma space as UIKit does.
        func composited(over background: RGB, opacity: Double) -> RGB {
            RGB(red: red * opacity + background.red * (1 - opacity),
                green: green * opacity + background.green * (1 - opacity),
                blue: blue * opacity + background.blue * (1 - opacity))
        }
    }

    /// The largest luminance white text can sit on and still reach 4.5:1.
    static let maxLuminanceForWhiteText = 1.05 / 4.5 - 0.05

    static func luminance(_ color: RGB) -> Double {
        0.2126 * linearize(color.red) + 0.7152 * linearize(color.green) + 0.0722 * linearize(color.blue)
    }

    static func luminance(hex: UInt32) -> Double {
        luminance(RGB(hex: hex))
    }

    /// The contrast ratio between two luminances, from 1 to 21.
    static func ratio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        ratio(luminance(a), luminance(b))
    }

    static func ratio(hex a: UInt32, _ b: UInt32) -> Double {
        ratio(luminance(hex: a), luminance(hex: b))
    }

    static func linearize(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

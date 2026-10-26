import Testing
import UIKit
@testable import Minidisc

/// WCAG AA contrast for every accent choice (accessibility audit 2026-10-25, H1 and H2).
@Suite("Accent contrast")
struct AccentContrastTests {
    private static let aa = 4.5

    @Test("White text on every accent fill reaches 4.5:1 in light and dark mode",
          arguments: AccentChoice.allCases)
    func whiteOnFill(_ accent: AccentChoice) {
        let (light, dark) = accent.hex
        #expect(WCAGContrast.ratio(hex: 0xFFFFFF, light) >= Self.aa, "\(accent) light")
        #expect(WCAGContrast.ratio(hex: 0xFFFFFF, dark) >= Self.aa, "\(accent) dark")
    }

    @Test("Dark variants sit in gold's luminance band", arguments: AccentChoice.allCases)
    func darkVariantsMatchGold(_ accent: AccentChoice) {
        let luminance = WCAGContrast.luminance(hex: accent.hex.dark)
        #expect((0.170...WCAGContrast.maxLuminanceForWhiteText).contains(luminance), "\(accent): \(luminance)")
    }

    /// System backgrounds, grouped backgrounds and raised rows in each appearance.
    private static let lightSurfaces: [UInt32] = [0xFFFFFF, 0xF2F2F7]
    private static let darkSurfaces: [UInt32] = [0x000000, 0x0F0D0C, 0x1C1C1E, 0x2C2C2E]
    /// Bordered buttons and link rows tint their background with the accent; 20% is above
    /// the strongest tint used (`.bordered`, and the 10% link-row background).
    private static let tint = 0.2

    @Test("The text shade reaches 4.5:1 on plain and accent-tinted surfaces",
          arguments: AccentChoice.allCases)
    func textOnSurfaces(_ accent: AccentChoice) {
        let cases: [(text: UInt32, fill: UInt32, surfaces: [UInt32], mode: String)] = [
            (accent.textHex.light, accent.hex.light, Self.lightSurfaces, "light"),
            (accent.textHex.dark, accent.hex.dark, Self.darkSurfaces, "dark"),
        ]
        for (text, fill, surfaces, mode) in cases {
            let textRGB = WCAGContrast.RGB(hex: text)
            for surface in surfaces.map(WCAGContrast.RGB.init(hex:)) {
                let backgrounds = [
                    surface,
                    textRGB.composited(over: surface, opacity: Self.tint),
                    WCAGContrast.RGB(hex: fill).composited(over: surface, opacity: Self.tint),
                ]
                for background in backgrounds {
                    let ratio = WCAGContrast.ratio(textRGB, background)
                    #expect(ratio >= Self.aa, "\(accent) \(mode) text on \(background): \(ratio)")
                }
            }
        }
    }

    @Test func goldHexMirrorsTheBrandAsset() {
        let asset = UIColor(resource: .minidiscBrandGold)
        #expect(Self.hex(asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))) == AccentChoice.gold.hex.light)
        #expect(Self.hex(asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))) == AccentChoice.gold.hex.dark)
    }

    private static func hex(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ c: CGFloat) -> UInt32 { UInt32((c * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

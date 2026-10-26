import SwiftUI
import Testing
@testable import Minidisc

/// Black or white content on cover colours, by WCAG contrast (contrast sweep 2026-10-26).
@Suite("Readable content")
struct ReadableContentTests {
    private static let grid: [WCAGContrast.RGB] = {
        let steps = (0...8).map { Double($0) / 8 }
        return steps.flatMap { r in steps.flatMap { g in steps.map { b in WCAGContrast.RGB(red: r, green: g, blue: b) } } }
    }()

    @Test func everyColourGetsAAPrimaryAndSecondaryText() {
        for color in Self.grid {
            let readable = ReadableContent.resolve(backgrounds: [color])
            #expect(ReadableContent.worstRatio(readable.content, on: readable.backgrounds) >= 4.5, "\(color)")
            #expect(ReadableContent.worstRatio(readable.content, on: readable.backgrounds,
                                               opacity: readable.secondaryOpacity) >= 4.5, "\(color)")
            #expect((0.7...1).contains(readable.secondaryOpacity))
        }
    }

    @Test func gradientsAreCheckedAtBothEnds() {
        let readable = ReadableContent.resolve(backgrounds: [WCAGContrast.RGB(hex: 0x3A6B2A), WCAGContrast.RGB(hex: 0x8FD16E)])
        #expect(ReadableContent.worstRatio(readable.content, on: readable.backgrounds) >= 4.5)
    }

    @Test func brightGreenGetsBlackText() {
        // Perceived brightness 0.59 kept white text here, at 1.4:1.
        let readable = ReadableContent.resolve(backgrounds: [WCAGContrast.RGB(red: 0, green: 1, blue: 0.06)])
        #expect(readable.usesDarkContent)
    }

    @Test func darkColoursAreLeftAlone() {
        let navy = WCAGContrast.RGB(hex: 0x16203A)
        let readable = ReadableContent.resolve(backgrounds: [navy])
        #expect(!readable.usesDarkContent)
        #expect(readable.backgrounds == [navy])
        #expect(readable.secondaryOpacity == 0.7)
    }

    @Test func midTonesMoveOnlyAsFarAsNeeded() {
        // Neither black nor white reaches 4.5:1 on this grey; it is nudged, not replaced.
        let grey = WCAGContrast.RGB(red: 0.46, green: 0.46, blue: 0.46)
        let readable = ReadableContent.resolve(backgrounds: [grey])
        let moved = readable.backgrounds[0]
        #expect(abs(moved.red - grey.red) < 0.08)
        #expect(ReadableContent.worstRatio(readable.content, on: [moved]) < 5)
    }

    @MainActor @Test func playlistThemeUsesTheResolution() {
        let green = PlaylistTheme(dominantColor: Color(red: 0, green: 1, blue: 0.06))
        #expect(green.isLight)
        #expect(green.contentColor == .black)
        let unresolved = PlaylistTheme(dominantColor: .clear)
        #expect(!unresolved.isThemed)
        #expect(unresolved.backgroundColor == .clear)
    }

    @MainActor @Test("Cover-colour album palettes reach 4.5:1 in both appearances",
                     arguments: [ColorScheme.light, .dark])
    func albumPalettes(_ scheme: ColorScheme) throws {
        let steps = (0...6).map { Double($0) / 6 }
        for r in steps { for g in steps { for b in steps {
            let palette = AlbumDetailPalette(dominantColor: Color(red: r, green: g, blue: b), appearance: scheme)
            let content = try #require(WCAGContrast.RGB(palette.contentColor.rgbComponents))
            var alpha: CGFloat = 0
            UIColor(palette.secondaryContentColor).getRed(nil, green: nil, blue: nil, alpha: &alpha)
            for stop in [palette.backgroundTopColor, palette.backgroundBottomColor] {
                let background = try #require(WCAGContrast.RGB(stop.rgbComponents))
                #expect(WCAGContrast.ratio(content, background) >= 4.5, "\(r) \(g) \(b) \(scheme)")
                let text = content.composited(over: background, opacity: Double(alpha))
                #expect(WCAGContrast.ratio(text, background) >= 4.5, "\(r) \(g) \(b) \(scheme) secondary")
            }
        } } }
    }
}

/// The Minidisc text colours on the Minidisc backgrounds (contrast sweep 2026-10-26).
@Suite("Minidisc text colours")
struct MinidiscTextColorTests {
    private static let backgrounds: [UIColor] = [
        UIColor(resource: .minidiscBackgroundPrimary),
        UIColor(resource: .minidiscBackgroundSecondary),
        UIColor(resource: .minidiscBackgroundTertiary),
    ]

    private static func rgb(_ color: UIColor, _ style: UIUserInterfaceStyle) -> WCAGContrast.RGB {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return WCAGContrast.RGB(red: Double(r), green: Double(g), blue: Double(b))
    }

    @Test("Secondary text reaches 4.5:1 and tertiary glyphs 3:1",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func textColours(_ style: UIUserInterfaceStyle) {
        let secondary = Self.rgb(UIColor(resource: .minidiscTextSecondary), style)
        let tertiary = Self.rgb(UIColor(resource: .minidiscTextTertiary), style)
        for background in Self.backgrounds.map({ Self.rgb($0, style) }) {
            #expect(WCAGContrast.ratio(secondary, background) >= 4.5, "\(background)")
            #expect(WCAGContrast.ratio(tertiary, background) >= 3, "\(background)")
        }
    }
}

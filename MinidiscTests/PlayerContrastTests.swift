import SwiftUI
import Testing
@testable import Minidisc

/// White content over the full player's artwork backdrop (contrast sweep 2026-10-26).
@Suite("Player contrast")
struct PlayerContrastTests {
    /// Every colour on a 13-step sRGB grid, darkened as the backdrop darkens a cover band.
    private static let backdrops: [WCAGContrast.RGB] = {
        let steps = (0...12).map { Double($0) / 12 }
        return steps.flatMap { r in steps.flatMap { g in steps.map { b in
            PlayerBackgroundPalette.capped(WCAGContrast.RGB(red: r, green: g, blue: b))
        } } }
    }()

    private static func worst(opacity: Double, over backgrounds: [WCAGContrast.RGB] = backdrops) -> Double {
        backgrounds.map { WCAGContrast.ratio(WCAGContrast.RGB.white.composited(over: $0, opacity: opacity), $0) }.min()!
    }

    @Test func backdropStopsStayUnderTheCap() {
        for stop in Self.backdrops {
            #expect(WCAGContrast.luminance(stop) <= PlayerBackgroundPalette.maxLuminance + 1e-9)
        }
    }

    @Test func secondaryTextReachesAA() {
        #expect(Self.worst(opacity: PlayerBackgroundPalette.secondaryOpacity) >= 4.5)
        // The previous 0.7 fell short on saturated reds, which is why the token exists.
        #expect(Self.worst(opacity: 0.7) < 4.5)
    }

    @Test func dimmedContentReachesThreeToOne() {
        #expect(Self.worst(opacity: PlayerBackgroundPalette.dimmedOpacity) >= 3)
    }

    @Test func inactiveQueuePillGlyphReachesThreeToOne() {
        let pills = Self.backdrops.map { WCAGContrast.RGB.white.composited(over: $0, opacity: 0.12) }
        #expect(Self.worst(opacity: PlayerBackgroundPalette.secondaryOpacity, over: pills) >= 3)
    }

    @Test("The active AirPlay tint, the accent's dark text shade, reaches 3:1 on the backdrop",
          arguments: AccentChoice.allCases)
    func airPlayActiveTint(_ accent: AccentChoice) {
        let tint = WCAGContrast.RGB(hex: accent.textHex.dark)
        let worst = Self.backdrops.map { WCAGContrast.ratio(tint, $0) }.min()!
        #expect(worst >= 3, "\(accent): \(worst)")
    }

    @Test @MainActor func colorsUseTheCap() throws {
        let white = try #require(PlayerBackgroundPalette.colors(from: [.white]).first?.rgbComponents)
        let expected = PlayerBackgroundPalette.capped(WCAGContrast.RGB.white)
        #expect(abs(white.red - expected.red) < 0.002)
        let pureRed = Color(red: 1, green: 0, blue: 0)
        for color in PlayerBackgroundPalette.colors(from: [.white, pureRed, .yellow, .black]) {
            let rgb = try #require(color.rgbComponents)
            #expect(PlayerBackgroundPalette.luminance(red: rgb.red, green: rgb.green, blue: rgb.blue)
                    <= PlayerBackgroundPalette.maxLuminance + 0.002)
        }
    }
}

/// Full-screen karaoke lyrics over the blurred cover (audit 2026-10-25 M3).
@Suite("Karaoke contrast")
struct KaraokeContrastTests {
    /// The brightest possible backdrop: a white cover at 55% over black, under the 45% scrim.
    private static let brightest = WCAGContrast.RGB.white.scaled(by: 0.55 * (1 - 0.45))

    @Test(arguments: [0.8, 0.6, 0.5])
    func dimmedLinesKeepLargeTextContrast(_ opacity: Double) {
        let line = WCAGContrast.RGB.white.composited(over: Self.brightest, opacity: opacity)
        #expect(WCAGContrast.ratio(line, Self.brightest) >= 3)
    }

    @Test func artistLineReachesAA() {
        let artist = WCAGContrast.RGB.white.composited(over: Self.brightest,
                                                       opacity: PlayerBackgroundPalette.secondaryOpacity)
        #expect(WCAGContrast.ratio(artist, Self.brightest) >= 4.5)
    }
}

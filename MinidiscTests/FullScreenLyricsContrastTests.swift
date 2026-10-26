import SwiftUI
import Testing
@testable import Minidisc

/// The Mac's full-screen lyrics over their vivid backdrop, with the dark washes behind the
/// lyrics and the song's text.
@Suite("Full-screen lyrics contrast")
struct FullScreenLyricsContrastTests {
    /// Every colour on a 13-step sRGB grid, made vivid as the backdrop makes a cover band.
    private static let backdrops: [WCAGContrast.RGB] = {
        let steps = (0...12).map { Double($0) / 12 }
        return steps.flatMap { r in steps.flatMap { g in steps.map { b in
            FullScreenLyricsBackdrop.vivid(WCAGContrast.RGB(red: r, green: g, blue: b))
        } } }
    }()

    private static func worst(opacity: Double, wash: Double) -> Double {
        backdrops.map { stop in
            let background = stop.scaled(by: 1 - wash)
            return WCAGContrast.ratio(WCAGContrast.RGB.white.composited(over: background, opacity: opacity), background)
        }.min()!
    }

    @Test func vividStopsStayUnderTheirCapAndAreBrighterThanThePlayers() {
        for stop in Self.backdrops {
            #expect(WCAGContrast.luminance(stop) <= FullScreenLyricsBackdrop.maxLuminance + 1e-9)
        }
        #expect(FullScreenLyricsBackdrop.maxLuminance > PlayerBackgroundPalette.maxLuminance * 2)
        // A muted purple keeps its hue and comes out brighter than the player would show it.
        let purple = FullScreenLyricsBackdrop.vivid(WCAGContrast.RGB(red: 0.4, green: 0.2, blue: 0.5))
        #expect(purple.blue > purple.red && purple.red > purple.green)
        #expect(WCAGContrast.luminance(purple) > PlayerBackgroundPalette.maxLuminance)
    }

    @Test func theLineBeingSungReadsEvenWithoutAWash() {
        #expect(Self.worst(opacity: 1, wash: 0) >= 3)
        #expect(Self.worst(opacity: 1, wash: FullScreenLyricsBackdrop.lyricsWashOpacity) >= 4.5)
    }

    @Test func theNearLinesKeepLargeTextContrastOnTheWash() {
        let wash = FullScreenLyricsBackdrop.lyricsWashOpacity
        let near = LyricsLineAppearance.line(atDistance: 1, depth: .deep, prefersLegibility: false)
        #expect(Self.worst(opacity: near.opacity, wash: wash) >= 3)
        // Increase Contrast and Reduce Transparency: every line, unblurred.
        for distance in 1...6 {
            let line = LyricsLineAppearance.line(atDistance: distance, depth: .deep, prefersLegibility: true)
            #expect(line.blur == 0)
            #expect(Self.worst(opacity: line.opacity, wash: wash) >= 3, "line \(distance)")
        }
    }

    @Test func theSongsTextReachesAAOnItsWash() {
        let wash = FullScreenLyricsBackdrop.textWashOpacity
        #expect(Self.worst(opacity: PlayerBackgroundPalette.secondaryOpacity, wash: wash) >= 4.5)
        #expect(Self.worst(opacity: 1, wash: wash) >= 4.5)
    }

    @Test @MainActor func coloursFromACoverStayUnderTheCap() throws {
        let samples: [Color] = [.white, Color(red: 0.6, green: 0.2, blue: 0.9), .yellow, .black]
        let colors = FullScreenLyricsBackdrop.colors(from: samples, accent: Color(red: 0.85, green: 0.65, blue: 0.2))
        #expect(colors.count == samples.count)
        for color in colors {
            let rgb = try #require(color.rgbComponents)
            #expect(PlayerBackgroundPalette.luminance(red: rgb.red, green: rgb.green, blue: rgb.blue)
                    <= FullScreenLyricsBackdrop.maxLuminance + 0.002)
        }
    }
}

/// How the lines around the one being sung recede.
@Suite("Lyric line depth")
struct LyricsLineDepthTests {
    @Test(arguments: [LyricsLineDepth.dimmed, .gentle, .deep])
    func theCurrentLineIsSharpAndFull(_ depth: LyricsLineDepth) {
        #expect(LyricsLineAppearance.line(atDistance: 0, depth: depth, prefersLegibility: false)
                == LyricsLineAppearance(opacity: 1, blur: 0))
    }

    @Test(arguments: [LyricsLineDepth.gentle, .deep])
    func linesFurtherOutBlurMoreAndFadeMore(_ depth: LyricsLineDepth) {
        let lines = (1...4).map { LyricsLineAppearance.line(atDistance: $0, depth: depth, prefersLegibility: false) }
        for (near, far) in zip(lines, lines.dropFirst()) {
            #expect(far.blur >= near.blur)
            #expect(far.opacity <= near.opacity)
        }
        #expect(lines[0].blur > 0)
    }

    @Test func fullScreenRecedesFurtherThanNowPlaying() {
        for distance in 1...4 {
            let deep = LyricsLineAppearance.line(atDistance: distance, depth: .deep, prefersLegibility: false)
            let gentle = LyricsLineAppearance.line(atDistance: distance, depth: .gentle, prefersLegibility: false)
            #expect(deep.blur > gentle.blur)
            #expect(deep.opacity <= gentle.opacity)
        }
        // The line before the current one: about half opacity, a couple of points of blur.
        let near = LyricsLineAppearance.line(atDistance: 1, depth: .deep, prefersLegibility: false)
        #expect((0.45...0.6).contains(near.opacity))
        #expect((2...3).contains(near.blur))
    }

    @Test func nowPlayingsNearLineAndLegibleLinesKeepThreeToOne() {
        // Over the player's backdrop, dimmedOpacity is the 3:1 opacity.
        let near = LyricsLineAppearance.line(atDistance: 1, depth: .gentle, prefersLegibility: false)
        #expect(near.opacity >= PlayerBackgroundPalette.dimmedOpacity)
        for distance in 1...6 {
            let line = LyricsLineAppearance.line(atDistance: distance, depth: .gentle, prefersLegibility: true)
            #expect(line == LyricsLineAppearance(opacity: PlayerBackgroundPalette.dimmedOpacity, blur: 0))
        }
        // The iPhone player only dims.
        #expect(LyricsLineAppearance.line(atDistance: 3, depth: .dimmed, prefersLegibility: false)
                == LyricsLineAppearance(opacity: PlayerBackgroundPalette.dimmedOpacity, blur: 0))
    }
}

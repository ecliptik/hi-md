import Foundation
import SwiftUI
import Testing
@testable import Minidisc

@Suite("Mac Now Playing and MiniPlayer presentation")
struct NowPlayingPresentationTests {
    @Test func lyricsFallBackToTheQueueWhenTheSongHasNone() {
        #expect(NowPlayingSidePane.resolved(.lyrics, canShowLyrics: true) == .lyrics)
        #expect(NowPlayingSidePane.resolved(.lyrics, canShowLyrics: false) == .queue)
        #expect(NowPlayingSidePane.resolved(.queue, canShowLyrics: true) == .queue)
        #expect(NowPlayingSidePane.resolved(.queue, canShowLyrics: false) == .queue)
        // Stored with @AppStorage by raw value.
        #expect(NowPlayingSidePane(rawValue: "lyrics") == .lyrics)
        #expect(NowPlayingSidePane(rawValue: "queue") == .queue)
    }

    @Test func subtitleJoinsArtistAndAlbum() {
        #expect(NowPlayingText.subtitle(artist: "Tatsuro Yamashita", album: "For You") == "Tatsuro Yamashita — For You")
        #expect(NowPlayingText.subtitle(artist: "亜蘭知子", album: nil) == "亜蘭知子")
        #expect(NowPlayingText.subtitle(artist: "  ", album: "Mint") == "Mint")
        #expect(NowPlayingText.subtitle(artist: nil, album: "") == nil)
    }

    @Test func secondaryTextKeepsAAContrastOnTheBrightestBackdrop() {
        let cap = NowPlayingText.backdropLuminanceCap
        #expect(NowPlayingText.contrastOfWhite(opacity: NowPlayingText.secondaryOpacity, backgroundLuminance: cap) >= 4.5)
        #expect(NowPlayingText.contrastOfWhite(opacity: NowPlayingText.primaryOpacity, backgroundLuminance: cap) >= 7)
        // And on black, the darkest backdrop.
        #expect(NowPlayingText.contrastOfWhite(opacity: NowPlayingText.secondaryOpacity, backgroundLuminance: 0) >= 4.5)
        // Plain .secondary-like 55% white would fail on the brightest backdrop, which is why the
        // views use their own opacity.
        #expect(NowPlayingText.contrastOfWhite(opacity: 0.55, backgroundLuminance: cap) < 4.5)
    }

    @Test @MainActor func theBackdropPaletteStaysUnderTheCap() {
        let samples: [Color] = [.white, .yellow, Color(red: 0.9, green: 0.95, blue: 1), .black]
        for color in PlayerBackgroundPalette.colors(from: samples) {
            guard let rgb = color.rgbComponents else { continue }
            let luminance = PlayerBackgroundPalette.luminance(red: rgb.red, green: rgb.green, blue: rgb.blue)
            #expect(luminance <= NowPlayingText.backdropLuminanceCap + 0.0001)
        }
    }

    @Test func luminanceAndSRGBRoundTrip() {
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            let luminance = NowPlayingText.luminance(ofGrey: value)
            #expect(abs(NowPlayingText.srgb(fromLuminance: luminance) - value) < 0.0001)
        }
    }

    @Test func clickingTheShownPaneHidesItAndClickingAgainBringsItBack() {
        // Lyrics on, click Lyrics: off.
        var next = NowPlayingSidePane.afterClicking(.lyrics, requested: .lyrics, isHidden: false, canShowLyrics: true)
        #expect(next.requested == .lyrics && next.isHidden)
        // Click Lyrics again: on.
        next = NowPlayingSidePane.afterClicking(.lyrics, requested: next.requested, isHidden: next.isHidden, canShowLyrics: true)
        #expect(next.requested == .lyrics && !next.isHidden)
        // Lyrics on, click Playing Next: switches without hiding.
        next = NowPlayingSidePane.afterClicking(.queue, requested: .lyrics, isHidden: false, canShowLyrics: true)
        #expect(next.requested == .queue && !next.isHidden)
        // Hidden, click Playing Next: shows the queue.
        next = NowPlayingSidePane.afterClicking(.queue, requested: .lyrics, isHidden: true, canShowLyrics: true)
        #expect(next.requested == .queue && !next.isHidden)
        // Lyrics asked for but the song has none, so the queue shows: clicking Playing Next hides it.
        next = NowPlayingSidePane.afterClicking(.queue, requested: .lyrics, isHidden: false, canShowLyrics: false)
        #expect(next.isHidden)
    }

    @Test func nowPlayingGrowsWithTheWindow() {
        let small = NowPlayingMetrics(width: 900, height: 640, showsPane: true)
        let medium = NowPlayingMetrics(width: 1000, height: 760, showsPane: true)
        let large = NowPlayingMetrics(width: 1728, height: 1080, showsPane: true)
        #expect(small.scale >= 1 && small.scale < 1.1)
        #expect(medium.scale > 1)
        #expect(large.scale > medium.scale && large.scale <= 1.6)
        #expect(large.artworkSide > medium.artworkSide)
        #expect(large.titleSize > medium.titleSize)
        #expect(large.playSize > medium.playSize)
        // The artwork never runs past its half or below the controls.
        for metrics in [small, medium, large] {
            #expect(metrics.artworkSide <= metrics.paneWidth + 0.001)
        }
        #expect(large.artworkSide + NowPlayingMetrics.controlsHeight(scale: large.scale)
                + 2 * NowPlayingMetrics.verticalInset <= 1080 + 0.001)
        // Without the side pane the player takes the middle and has no pane.
        let alone = NowPlayingMetrics(width: 1000, height: 900, showsPane: false)
        #expect(alone.paneWidth == 0)
        #expect(alone.artworkSide > medium.artworkSide)
    }

    @Test func macLyricsAreLargeAndScaleWithThePane() {
        #expect(LyricsTypography.iPhone.lineSize == nil)
        let beside = LyricsTypography.scaled(forWidth: 424)
        let fullScreen = LyricsTypography.scaled(forWidth: 800)
        let narrow = LyricsTypography.scaled(forWidth: 200)
        #expect((28...32).contains(beside.lineSize ?? 0))
        #expect(fullScreen.lineSize == 40)
        #expect(narrow.lineSize == 22)
        #expect(LyricsTypography.scaled(forWidth: 200, minimum: 18).lineSize == 18)
        #expect(fullScreen.lineSpacing > beside.lineSpacing)
        // The MiniPlayer and Now Playing move the buttons out from above the lines.
        #expect(LyricsTypography.iPhone.showsHeaderButtons)
        #expect(!beside.withoutHeaderButtons().showsHeaderButtons)
        #expect(beside.withoutHeaderButtons().lineSize == beside.lineSize)
    }

    @Test func fullScreenLyricsScaleFrom48To72() {
        #expect(LyricsTypography.iPhone.karaokeLineSize == nil)
        #expect(LyricsTypography.karaoke(forWidth: 900).karaokeLineSize == 48)
        #expect(LyricsTypography.karaoke(forWidth: 1200).karaokeLineSize == 60)
        #expect(LyricsTypography.karaoke(forWidth: 2560).karaokeLineSize == 72)
        #expect(!LyricsTypography.karaoke(forWidth: 1200).showsHeaderButtons)
    }

    @Test func aGreyCoverGetsATintedBackdropThatKeepsContrast() {
        let gold = WCAGContrast.RGB(red: 0.85, green: 0.65, blue: 0.2)
        let white = WCAGContrast.RGB.white
        let tinted = PlayerBackgroundPalette.tinted(white, toward: gold, fraction: 0)
        #expect(tinted != white)
        #expect(tinted.blue < tinted.red)
        // The top stop takes more of the accent than the bottom one.
        let bottom = PlayerBackgroundPalette.tinted(white, toward: gold, fraction: 1)
        #expect(white.blue - tinted.blue > white.blue - bottom.blue)
        // A black sleeve gets a tint too; a coloured cover keeps its colour.
        #expect(PlayerBackgroundPalette.tinted(.black, toward: gold, fraction: 0) != .black)
        let red = WCAGContrast.RGB(red: 0.8, green: 0.1, blue: 0.1)
        #expect(PlayerBackgroundPalette.tinted(red, toward: gold, fraction: 0) == red)
        // Once capped, white text still has its contrast.
        for color in [white, .black, WCAGContrast.RGB(red: 0.5, green: 0.5, blue: 0.5)] {
            let stop = PlayerBackgroundPalette.capped(PlayerBackgroundPalette.tinted(color, toward: gold, fraction: 0.5))
            #expect(WCAGContrast.luminance(stop) <= NowPlayingText.backdropLuminanceCap + 0.0001)
        }
    }

    @Test @MainActor func tintedBackdropStaysUnderTheCap() {
        let samples: [Color] = [.white, .white, Color(white: 0.9), .black]
        let colors = PlayerBackgroundPalette.tintedColors(from: samples, accent: Color(red: 0.85, green: 0.65, blue: 0.2))
        #expect(colors.count == samples.count)
        for color in colors {
            guard let rgb = color.rgbComponents else { continue }
            #expect(PlayerBackgroundPalette.luminance(red: rgb.red, green: rgb.green, blue: rgb.blue)
                    <= NowPlayingText.backdropLuminanceCap + 0.0001)
        }
    }
}

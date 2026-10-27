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

    @Test func playerTypeAndControlsGrowOnlyGently() {
        // Apple Music's proportions at about 1,470 × 900: a 15–17 point title on one line, a
        // 13–14 point subtitle, a 20–24 point transport with a play button around 28–32.
        let music = NowPlayingControlSizes(windowWidth: 1470)
        #expect((15...17).contains(music.titleSize))
        #expect((13...14).contains(music.subtitleSize))
        #expect((20...24).contains(music.transportSize))
        #expect((28...32).contains(music.playSize))
        #expect((22...26).contains(music.songButtonSize))
        // 900 points and less start at the smallest sizes; 2,560 and more end at the largest.
        for width in [600.0, 900] {
            let small = NowPlayingControlSizes(windowWidth: width)
            #expect([small.titleSize, small.subtitleSize, small.transportSize, small.playSize, small.timeSize]
                    == [15, 13, 20, 28, 10])
        }
        for width in [2560.0, 3840] {
            let large = NowPlayingControlSizes(windowWidth: width)
            #expect([large.titleSize, large.subtitleSize, large.transportSize, large.playSize, large.timeSize]
                    == [20, 16, 28, 38, 12])
        }
        // Both players use them, whatever the artwork does.
        for (width, height) in [(1000.0, 700.0), (1470, 900), (1728, 1080), (2560, 1440)] {
            let controls = NowPlayingControlSizes(windowWidth: width)
            let nowPlaying = NowPlayingMetrics(width: width, height: height, showsPane: true)
            let fullScreen = FullScreenLyricsMetrics(width: width, height: height)
            #expect(nowPlaying.controls == controls && fullScreen.controls == controls)
            #expect(nowPlaying.titleSize == controls.titleSize && fullScreen.playSize == controls.playSize)
            // The title and the subtitle fit their one line beside the buttons in the column.
            #expect(nowPlaying.titleSize <= 20 && fullScreen.titleSize <= 20)
            #expect(fullScreen.artworkSide > 4 * fullScreen.songButtonSize)
        }
    }

    @Test func subtitlePartsLeaveOutWhatIsMissing() {
        let both = NowPlayingText.subtitleParts(artist: " The Jesus and Mary Chain ", album: "The Magnificent Tree")
        #expect(both.artist == "The Jesus and Mary Chain" && both.album == "The Magnificent Tree")
        let noAlbum = NowPlayingText.subtitleParts(artist: "Low", album: "  ")
        #expect(noAlbum.artist == "Low" && noAlbum.album == nil)
        let neither = NowPlayingText.subtitleParts(artist: "", album: nil)
        #expect(neither.artist == nil && neither.album == nil)
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

    @Test func fullScreenLyricsAreAbout60PointsInA1000PointWindowAndScale() {
        let medium = FullScreenLyricsMetrics(width: 1000, height: 700)
        #expect((56...64).contains(medium.lineSize))
        let small = FullScreenLyricsMetrics(width: 900, height: 600)
        let large = FullScreenLyricsMetrics(width: 1512, height: 982)
        let huge = FullScreenLyricsMetrics(width: 2560, height: 1440)
        #expect(small.lineSize <= medium.lineSize)
        #expect(large.lineSize > medium.lineSize)
        #expect(huge.lineSize >= large.lineSize)
        #expect(huge.lineSize <= 84)
        // The typography the lines get: huge, left-aligned, the deep depth of field, no buttons.
        let typography = LyricsTypography.fullScreen(medium)
        #expect(typography.lineSize == medium.lineSize)
        #expect(typography.depth == .deep)
        #expect(!typography.showsHeaderButtons)
        #expect(LyricsTypography.iPhone.depth == .dimmed)
    }

    @Test func fullScreenLyricsSplitTheWindowIntoTwoColumns() {
        for (width, height) in [(900.0, 600.0), (1000, 700), (1512, 982), (2560, 1440)] {
            let metrics = FullScreenLyricsMetrics(width: width, height: height)
            // The artwork column is about 40% of the window, the lyrics take the rest.
            #expect((0.28...0.42).contains(metrics.artworkSide / width), "\(width)×\(height)")
            let used = 2 * metrics.horizontalInset + metrics.artworkSide + metrics.columnGap + metrics.lyricsWidth
            #expect(abs(used - width) < 0.5)
            // The artwork and its controls fit the height.
            #expect(metrics.artworkSide + FullScreenLyricsMetrics.controlsHeight(scale: metrics.scale)
                    + 2 * metrics.verticalInset <= height + 0.5)
            // About four lines show, and a line holds more than a word or two.
            let pitch = metrics.lineSize * 1.25 + metrics.lineSpacing
            #expect(metrics.lyricsHeight / pitch <= FullScreenLyricsMetrics.visibleLines + 0.01)
            #expect(metrics.lyricsHeight / pitch >= 3)
            #expect(metrics.lyricsWidth / metrics.lineSize >= 7)
        }
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

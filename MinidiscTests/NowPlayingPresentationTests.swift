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

    @Test func miniPlayerSizes() {
        #expect(MiniPlayerLayout.height(expanded: false) == MiniPlayerLayout.compactHeight)
        #expect(MiniPlayerLayout.height(expanded: true) == MiniPlayerLayout.expandedHeight)
        #expect(MiniPlayerLayout.minimumExpandedHeight > MiniPlayerLayout.compactHeight)
        #expect(MiniPlayerLayout.expandedHeight >= MiniPlayerLayout.minimumExpandedHeight)
    }
}

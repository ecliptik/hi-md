import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

@Suite("Mac MiniPlayer layouts, tabs and details")
struct MiniPlayerPresentationTests {
    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Song \(id)", artist: "Artist", albumId: "album", albumName: "Album", artistId: "artist",
            genre: nil, duration: 200, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: "flac",
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    // MARK: Layout

    @Test func theWindowShapeChoosesTheLayout() {
        let width = MiniPlayerLayout.defaultWidth
        #expect(MiniPlayerLayout.layout(for: CGSize(width: width, height: MiniPlayerLayout.compactHeight(forWidth: width))) == .compact)
        #expect(MiniPlayerLayout.layout(for: CGSize(width: width, height: MiniPlayerLayout.tallHeight(forWidth: width))) == .tall)
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 620, height: 260)) == .wide)
        // A large square window stays compact, with a bigger artwork.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 500, height: 640)) == .compact)
        // Narrow but short isn't tall enough for the tabs.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 260, height: 500)) == .compact)
        // The smallest window and an unsized one still get a layout.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: MiniPlayerLayout.minimumWidth,
                                                    height: MiniPlayerLayout.minimumHeight)) == .compact)
        #expect(MiniPlayerLayout.layout(for: .zero) == .compact)
    }

    @Test func theChevronExpandsAndCollapses() {
        let compact = CGSize(width: 300, height: MiniPlayerLayout.compactHeight(forWidth: 300))
        let expanded = MiniPlayerLayout.toggledSize(from: compact)
        #expect(expanded.width == 300)
        #expect(MiniPlayerLayout.layout(for: expanded) == .tall)
        let collapsed = MiniPlayerLayout.toggledSize(from: expanded)
        #expect(collapsed == compact)
        // Wide expands to a tall window about as wide as its artwork.
        let fromWide = MiniPlayerLayout.toggledSize(from: CGSize(width: 640, height: 300))
        #expect(fromWide.width == 300)
        #expect(MiniPlayerLayout.layout(for: fromWide) == .tall)
        #expect(MiniPlayerLayout.compact.expands && MiniPlayerLayout.wide.expands && !MiniPlayerLayout.tall.expands)
    }

    @Test func theWindowCantBecomeAStrip() {
        // Wide stops at 3:1, tall at 1:3.2.
        #expect(MiniPlayerLayout.maximumContentSize(for: CGSize(width: 600, height: 260)).width == 780)
        #expect(MiniPlayerLayout.maximumContentSize(for: CGSize(width: 300, height: 446)).height == 960)
        // The owner's 1370 x 380 window comes back to 3:1.
        let strip = MiniPlayerLayout.clamped(CGSize(width: 1370, height: 380))
        #expect(strip == CGSize(width: 1140, height: 380))
        #expect(MiniPlayerLayout.layout(for: strip) == .wide)
        #expect(MiniPlayerLayout.clamped(CGSize(width: 260, height: 2000)).height == 832)
        #expect(MiniPlayerLayout.clamped(CGSize(width: 100, height: 100)) == CGSize(width: 260, height: 220))
        // Sizes inside the limits are left alone, including every layout's own.
        for size in [CGSize(width: 300, height: 446), CGSize(width: 300, height: 750), CGSize(width: 620, height: 260)] {
            #expect(MiniPlayerLayout.clamped(size) == size)
        }
    }

    @Test func theArtworkFitsEachLayout() {
        let compact = CGSize(width: 300, height: MiniPlayerLayout.compactHeight(forWidth: 300))
        #expect(MiniPlayerLayout.compact.artworkSide(in: compact) == 300 - 2 * MiniPlayerLayout.inset)
        let tall = CGSize(width: 300, height: MiniPlayerLayout.tallHeight(forWidth: 300))
        let tallSide = MiniPlayerLayout.tall.artworkSide(in: tall)
        #expect(tallSide <= 300 - 2 * MiniPlayerLayout.inset)
        #expect(tallSide + MiniPlayerLayout.tallChrome + MiniPlayerLayout.minimumPanelHeight
                + MiniPlayerLayout.inset <= tall.height)
        let wide = CGSize(width: 620, height: 260)
        #expect(MiniPlayerLayout.wide.artworkSide(in: wide) == 260 - 2 * MiniPlayerLayout.inset)
    }

    // MARK: Tabs and lyrics

    @Test func lyricsTurnOnAndOffAndTheTabComesBack() {
        var state = MiniPlayerPanelState(tab: .related, showsLyrics: false)
        state.toggleLyrics()
        #expect(state.isShowingLyrics(canShowLyrics: true))
        #expect(!state.isSelected(.related, canShowLyrics: true))
        state.toggleLyrics()
        #expect(!state.isShowingLyrics(canShowLyrics: true))
        #expect(state.isSelected(.related, canShowLyrics: true))
        // Choosing a tab while lyrics are on turns them off.
        state.toggleLyrics()
        state.select(.history)
        #expect(!state.showsLyrics)
        #expect(state.isSelected(.history, canShowLyrics: true))
        // A song without lyrics shows the tab even with lyrics on.
        state.toggleLyrics()
        #expect(!state.isShowingLyrics(canShowLyrics: false))
        #expect(state.isSelected(.history, canShowLyrics: false))
        // Stored with @AppStorage by raw value.
        #expect(MiniPlayerTab(rawValue: "upNext") == .upNext)
    }

    // MARK: History and related songs

    @Test func historyListsEarlierSongsMostRecentFirst() {
        let queue = ["a", "b", "c", "d", "e"].map(song)
        let history = QueueHistory.earlier(in: queue, currentIndex: 3)
        #expect(history.map(\.song.id) == ["c", "b", "a"])
        #expect(history.map(\.index) == [2, 1, 0])
        #expect(QueueHistory.earlier(in: queue, currentIndex: 0).isEmpty)
        #expect(QueueHistory.earlier(in: [], currentIndex: 2).isEmpty)
        #expect(QueueHistory.earlier(in: queue, currentIndex: 4, limit: 2).map(\.song.id) == ["d", "c"])
        // A stale index past the end lists the whole queue.
        #expect(QueueHistory.earlier(in: queue, currentIndex: 9).count == 5)
    }

    @Test func relatedSongsDropTheSongPlayingAndRepeats() {
        let songs = ["now", "x", "y", "x", "z"].map(song)
        #expect(RelatedSongs.filtered(songs, excluding: "now").map(\.id) == ["x", "y", "z"])
        #expect(RelatedSongs.filtered(songs, excluding: nil).map(\.id) == ["now", "x", "y", "z"])
    }

    // MARK: Format

    @Test func theFormatLabelSaysWhatIsPlaying() {
        // A cached Opus conversion of a FLAC file.
        #expect(NowPlayingFormat.label(originalSuffix: "flac", originalBitRate: 900, localFileExtension: "opus",
                                       streamRequest: nil) == "Opus")
        // The downloaded original.
        #expect(NowPlayingFormat.label(originalSuffix: "flac", originalBitRate: 900, localFileExtension: "flac",
                                       streamRequest: nil) == "FLAC")
        // Streaming the original, or a conversion.
        #expect(NowPlayingFormat.label(originalSuffix: "flac", originalBitRate: 900, localFileExtension: nil,
                                       streamRequest: .original) == "FLAC")
        #expect(NowPlayingFormat.label(originalSuffix: "flac", originalBitRate: 900, localFileExtension: nil,
                                       streamRequest: StreamRequest(format: "mp3", maxBitRate: 320)) == "MP3")
        // An unknown cached container falls back to the original.
        #expect(NowPlayingFormat.label(originalSuffix: "mp3", originalBitRate: 320, localFileExtension: "bin",
                                       streamRequest: nil) == "MP3")
        // MPEG-4: lossless ALAC or AAC by bitrate.
        #expect(NowPlayingFormat.label(originalSuffix: "m4a", originalBitRate: 1_000, localFileExtension: "m4a",
                                       streamRequest: nil) == "ALAC")
        #expect(NowPlayingFormat.codecName("m4a", bitRate: 256) == "AAC")
        #expect(NowPlayingFormat.codecName("raw", bitRate: nil) == nil)
        #expect(NowPlayingFormat.label(originalSuffix: nil, originalBitRate: nil, localFileExtension: nil,
                                       streamRequest: nil) == nil)
    }
}

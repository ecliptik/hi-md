import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

@Suite("Mac MiniPlayer layouts, panes and details")
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
        // Below the traffic lights' band, and the inset at the bottom.
        let wide = CGSize(width: 620, height: 260)
        #expect(MiniPlayerLayout.wide.artworkSide(in: wide) == 260 - MiniPlayerLayout.titleBarBand - MiniPlayerLayout.inset)
    }

    @Test func contentStartsBelowTheTrafficLights() {
        // The measured band pushes every layout's top down; without buttons the inset is left.
        #expect(MiniPlayerLayout.topSpace(28) == 28)
        #expect(MiniPlayerLayout.topSpace(0) == MiniPlayerLayout.inset)
        #expect(MiniPlayerLayout.compactHeight(forWidth: 300, topInset: 32) == 32 + 272 + MiniPlayerLayout.compactChrome)
        #expect(MiniPlayerLayout.compactHeight(forWidth: 300, topInset: 0)
                == MiniPlayerLayout.inset + 272 + MiniPlayerLayout.compactChrome)
        let wide = CGSize(width: 700, height: 300)
        #expect(MiniPlayerLayout.wide.artworkSide(in: wide, topInset: 40) == 300 - 40 - MiniPlayerLayout.inset)
        let compact = CGSize(width: 300, height: 600)
        #expect(MiniPlayerLayout.compact.artworkSide(in: compact, topInset: 40) <= 600 - 40 - MiniPlayerLayout.compactChrome)
    }

    // MARK: Panes

    @Test func eachLayoutShowsThePaneItCan() {
        #expect(!MiniPlayerLayout.compact.showsPane(isOpen: true))
        #expect(MiniPlayerLayout.tall.showsPane(isOpen: false))
        #expect(MiniPlayerLayout.wide.showsPane(isOpen: true))
        #expect(!MiniPlayerLayout.wide.showsPane(isOpen: false))
        // Stored with @AppStorage by raw value.
        #expect(MiniPlayerPane(rawValue: "library") == .library)
        #expect(MiniPlayerPane(rawValue: "lyrics") == .lyrics)
    }

    @Test func tabsSelectAPane() {
        var state = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        state.select(.library)
        #expect(state.isShowing(.library, in: .tall, canShowLyrics: true))
        #expect(state.isShowing(.library, in: .wide, canShowLyrics: true))
        #expect(!state.isShowing(.library, in: .compact, canShowLyrics: true))
        // A song without lyrics shows Playing Next in their place.
        state.select(.lyrics)
        #expect(state.shownPane(canShowLyrics: false) == .upNext)
        #expect(state.isShowing(.upNext, in: .tall, canShowLyrics: false))
        #expect(state.isShowing(.lyrics, in: .tall, canShowLyrics: true))
    }

    @Test func compactGrowsToShowThePaneAndCollapsesBack() {
        var state = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        #expect(state.toggle(.lyrics, in: .compact, canShowLyrics: true, grewFromCompact: false) == .grow)
        #expect(state.pane == .lyrics && state.isOpen)
        // Grown wide: clicking Lyrics again goes back to compact.
        #expect(state.toggle(.lyrics, in: .wide, canShowLyrics: true, grewFromCompact: true) == .collapse)
        #expect(!state.isOpen)
        // Grown tall: the same.
        #expect(state.toggle(.library, in: .compact, canShowLyrics: true, grewFromCompact: false) == .grow)
        #expect(state.toggle(.library, in: .tall, canShowLyrics: true, grewFromCompact: true) == .collapse)
        // On a compact window the buttons are never on, so a click always grows it.
        #expect(state.toggle(.library, in: .compact, canShowLyrics: true, grewFromCompact: false) == .grow)
    }

    @Test func wideOpensAndClosesItsPaneInPlace() {
        var state = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        #expect(state.toggle(.library, in: .wide, canShowLyrics: true, grewFromCompact: false) == .show)
        #expect(state.isShowing(.library, in: .wide, canShowLyrics: true))
        // The other button switches the pane rather than closing it.
        #expect(state.toggle(.lyrics, in: .wide, canShowLyrics: true, grewFromCompact: false) == .show)
        #expect(state.pane == .lyrics)
        #expect(state.toggle(.lyrics, in: .wide, canShowLyrics: true, grewFromCompact: false) == .close)
        #expect(!state.isOpen)
        // A tall window shows the tab; clicking the one on screen collapses it to compact.
        #expect(state.toggle(.library, in: .tall, canShowLyrics: true, grewFromCompact: false) == .show)
        #expect(state.toggle(.library, in: .tall, canShowLyrics: true, grewFromCompact: false) == .collapse)
    }

    @Test func aCompactWindowGrowsToTheCloserLayoutThatFits() {
        let compact = CGSize(width: 300, height: MiniPlayerLayout.compactHeight(forWidth: 300))
        let wide = MiniPlayerLayout.wideSize(fromCompact: compact)
        #expect(MiniPlayerLayout.layout(for: wide) == .wide)
        // An artwork at least as big as the compact one, beside a pane with room to show.
        #expect(MiniPlayerLayout.wide.artworkSide(in: wide) >= MiniPlayerLayout.compact.artworkSide(in: compact))
        #expect(Double(wide.height) >= MiniPlayerLayout.titleBarBand + MiniPlayerLayout.inset
                + MiniPlayerLayout.wideDetailsChrome + MiniPlayerLayout.wideMinimumPaneHeight)
        #expect(MiniPlayerLayout.clamped(wide) == wide)

        let tall = CGSize(width: 300, height: MiniPlayerLayout.tallHeight(forWidth: 300))
        // With room for both, the smaller change: tall for the default window.
        #expect(MiniPlayerLayout.grownSize(fromCompact: compact, available: nil) == tall)
        // A short screen can't fit the tall window, so it grows wide.
        #expect(MiniPlayerLayout.grownSize(fromCompact: compact, available: CGSize(width: 1400, height: 600)) == wide)
        // Fitting neither, wide, the shorter.
        #expect(MiniPlayerLayout.grownSize(fromCompact: compact, available: CGSize(width: 320, height: 500)) == wide)
        // A big square compact window is closer to wide.
        let big = CGSize(width: 520, height: MiniPlayerLayout.compactHeight(forWidth: 520))
        #expect(MiniPlayerLayout.layout(for: MiniPlayerLayout.grownSize(fromCompact: big, available: nil)) == .wide)
    }

    @Test func collapsingFindsACompactWindow() {
        let tall = CGSize(width: 300, height: 750)
        #expect(MiniPlayerLayout.collapsedSize(from: tall)
                == CGSize(width: 300, height: MiniPlayerLayout.compactHeight(forWidth: 300)))
        let wide = CGSize(width: 700, height: 360)
        let collapsed = MiniPlayerLayout.collapsedSize(from: wide)
        #expect(MiniPlayerLayout.layout(for: collapsed) == .compact)
        // About as wide as the wide window's artwork (318 points), with its insets.
        #expect(collapsed == CGSize(width: 346, height: MiniPlayerLayout.compactHeight(forWidth: 346)))
        let compact = CGSize(width: 300, height: 460)
        #expect(MiniPlayerLayout.collapsedSize(from: compact) == compact)
    }

    @Test func aShortWideWindowGrowsForItsPane() {
        let grown = MiniPlayerLayout.wideSizeShowingPane(from: CGSize(width: 620, height: 260))
        #expect(grown?.width == 620)
        #expect(grown.map { MiniPlayerLayout.layout(for: $0) } == .wide)
        #expect((grown?.height ?? 0) > 260)
        // Already tall enough, or not wide: nothing to do.
        #expect(MiniPlayerLayout.wideSizeShowingPane(from: CGSize(width: 800, height: 420)) == nil)
        #expect(MiniPlayerLayout.wideSizeShowingPane(from: CGSize(width: 300, height: 460)) == nil)
        // Taller would stop it being wide, so it widens too.
        let narrow = MiniPlayerLayout.wideSizeShowingPane(from: CGSize(width: 400, height: 260))
        #expect(narrow.map { MiniPlayerLayout.layout(for: $0) } == .wide)
    }

    // MARK: Moving songs in Up Next

    @Test func moveUpAndDownStepOnePlace() {
        // Up Next is queue places 3, 4, 5 and 6 of a seven-song queue.
        let places = [3, 4, 5, 6]
        func destination(_ position: Int, _ delta: Int) -> Int? {
            QueueStep.destination(movingPosition: position, by: delta, upcomingCount: places.count,
                                  queueIndex: { places[$0] }, queueCount: 7)
        }
        #expect(destination(1, -1) == 3)
        #expect(destination(1, 1) == 6)
        // Down from the second to last goes past the end.
        #expect(destination(2, 1) == 7)
        #expect(destination(0, -1) == nil)
        #expect(destination(3, 1) == nil)
        #expect(destination(9, 1) == nil)
        #expect(destination(1, 2) == nil)
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

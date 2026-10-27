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

    private let square = CGSize(width: MiniPlayerLayout.defaultSide, height: MiniPlayerLayout.defaultSide)

    // MARK: Layout

    @Test func withoutAPaneTheWindowIsOnlyTheArtwork() {
        #expect(MiniPlayerLayout.layout(for: square, isPaneOpen: false) == .compact)
        // Whatever its shape, a window without a pane is compact, and the artwork fills it.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 900, height: 300), isPaneOpen: false) == .compact)
        #expect(MiniPlayerLayout.compact.artworkSide(in: square) == MiniPlayerLayout.defaultSide)
        #expect(MiniPlayerLayout.compact.paneSize(in: square) == .zero)
        #expect(MiniPlayerLayout.layout(for: .zero, isPaneOpen: true) == .compact)
    }

    @Test func aPaneGoesUnderTheArtworkOrBesideIt() {
        let tall = CGSize(width: 320, height: 660)
        #expect(MiniPlayerLayout.layout(for: tall, isPaneOpen: true) == .tall)
        #expect(MiniPlayerLayout.tall.artworkSide(in: tall) == 320)
        #expect(MiniPlayerLayout.tall.paneSize(in: tall) == CGSize(width: 320, height: 340))
        let wide = CGSize(width: 660, height: 320)
        #expect(MiniPlayerLayout.layout(for: wide, isPaneOpen: true) == .wide)
        #expect(MiniPlayerLayout.wide.artworkSide(in: wide) == 320)
        #expect(MiniPlayerLayout.wide.paneSize(in: wide) == CGSize(width: 340, height: 320))
        // Not wide enough for the pane beside the artwork: it goes under it.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 590, height: 320), isPaneOpen: true) == .tall)
        // A pane never shrinks below its least room; the artwork gives way.
        #expect(MiniPlayerLayout.tall.artworkSide(in: CGSize(width: 400, height: 500)) == 300)
        #expect(MiniPlayerLayout.wide.artworkSide(in: CGSize(width: 700, height: 500)) == 420)
    }

    @Test func eachLayoutHasSensibleLimits() {
        #expect(MiniPlayerLayout.compact.minimumSize == CGSize(width: 260, height: 260))
        #expect(MiniPlayerLayout.compact.maximumSize == CGSize(width: 720, height: 720))
        #expect(MiniPlayerLayout.tall.minimumSize == CGSize(width: 260, height: 460))
        #expect(MiniPlayerLayout.wide.minimumSize == CGSize(width: 540, height: 260))
        #expect(MiniPlayerLayout.compactSize(side: 100) == CGSize(width: 260, height: 260))
        #expect(MiniPlayerLayout.compactSize(side: 2000) == CGSize(width: 720, height: 720))
        #expect(MiniPlayerLayout.compactSize(side: 333.4) == CGSize(width: 333, height: 333))
    }

    // MARK: Hugging the content

    @Test func openingAPaneAddsAModestHeightUnderTheArtwork() {
        let opened = MiniPlayerLayout.openedSize(fromCompact: square, available: CGSize(width: 1600, height: 1000))
        #expect(opened == CGSize(width: 320, height: 320 + MiniPlayerLayout.paneHeight))
        #expect(MiniPlayerLayout.layout(for: opened, isPaneOpen: true) == .tall)
        // About seven rows, never a screenful of empty space.
        #expect(MiniPlayerLayout.paneHeight >= 320 && MiniPlayerLayout.paneHeight <= 380)
        // The artwork keeps its size.
        #expect(MiniPlayerLayout.tall.artworkSide(in: opened) == 320)
        #expect(MiniPlayerLayout.openedSize(fromCompact: square, available: nil) == opened)
    }

    @Test func withoutRoomBelowThePaneOpensBesideTheArtwork() {
        let opened = MiniPlayerLayout.openedSize(fromCompact: square, available: CGSize(width: 1600, height: 500))
        #expect(opened == CGSize(width: 320 + MiniPlayerLayout.paneWidth, height: 320))
        #expect(MiniPlayerLayout.layout(for: opened, isPaneOpen: true) == .wide)
        #expect(MiniPlayerLayout.wide.artworkSide(in: opened) == 320)
        // Room for neither: under it, as tall as the screen allows.
        let cramped = MiniPlayerLayout.openedSize(fromCompact: square, available: CGSize(width: 500, height: 590.6))
        #expect(cramped == CGSize(width: 320, height: 590))
    }

    @Test func closingAPaneGoesBackToExactlyTheSizeBefore() {
        var sizing = MiniPlayerWindowSizing()
        let compact = CGSize(width: 347, height: 347)
        let opened = sizing.sizeOpeningPane(from: compact, available: nil)
        #expect(opened == CGSize(width: 347, height: 687))
        // Resized by hand while the pane was open: closing still goes back.
        #expect(sizing.sizeClosingPane(from: CGSize(width: 500, height: 900)) == compact)
        #expect(sizing.compactSize == nil)
        // Open at launch, so no size to go back to: as big as the artwork was.
        #expect(sizing.sizeClosingPane(from: CGSize(width: 400, height: 800)) == CGSize(width: 400, height: 400))
        #expect(sizing.sizeClosingPane(from: CGSize(width: 800, height: 380)) == CGSize(width: 380, height: 380))
    }

    @Test func aRestoredWindowFitsThePaneState() {
        // An older version's tall window, with no pane open now, becomes a square of its width.
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 300, height: 750), isPaneOpen: false)
                == CGSize(width: 300, height: 300))
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 1370, height: 380), isPaneOpen: false)
                == CGSize(width: 380, height: 380))
        // A pane open in a square window gets its least room under the artwork.
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 320, height: 320), isPaneOpen: true)
                == CGSize(width: 320, height: 520))
        // Sizes that already fit are left alone.
        for size in [CGSize(width: 320, height: 660), CGSize(width: 700, height: 320)] {
            #expect(MiniPlayerLayout.reconciled(size, isPaneOpen: true) == size)
        }
        #expect(MiniPlayerLayout.reconciled(square, isPaneOpen: false) == square)
    }

    // MARK: Panes

    @Test func lyricsAndQueueToggleTheirPane() {
        var state = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        #expect(state.toggle(.upNext, canShowLyrics: true) == .open)
        #expect(state.isShowing(.upNext, canShowLyrics: true))
        // The other button switches the pane rather than closing it.
        #expect(state.toggle(.lyrics, canShowLyrics: true) == .switchPane)
        #expect(state.pane == .lyrics)
        // Clicking the one that's on closes it.
        #expect(state.toggle(.lyrics, canShowLyrics: true) == .close)
        #expect(!state.isOpen)
        #expect(!state.isShowing(.lyrics, canShowLyrics: true))
        #expect(state.close() == .none)
    }

    @Test func theMenuOpensLibraryAndRelated() {
        var state = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        #expect(state.show(.library, canShowLyrics: true) == .open)
        #expect(state.show(.library, canShowLyrics: true) == .none)
        #expect(state.show(.related, canShowLyrics: true) == .switchPane)
        // From Related, Queue switches; clicking it again closes.
        #expect(state.toggle(.upNext, canShowLyrics: true) == .switchPane)
        #expect(state.close() == .close)
        // Stored with @AppStorage by raw value.
        #expect(MiniPlayerPane(rawValue: "library") == .library)
        #expect(MiniPlayerPane(rawValue: "upNext") == .upNext)
    }

    @Test func aSongWithoutLyricsShowsTheQueue() {
        var state = MiniPlayerPanelState(pane: .lyrics, isOpen: true)
        #expect(state.shownPane(canShowLyrics: false) == .upNext)
        #expect(state.isShowing(.upNext, canShowLyrics: false))
        #expect(!state.isShowing(.lyrics, canShowLyrics: false))
        // Queue is the one on, so clicking it closes the pane.
        #expect(state.toggle(.upNext, canShowLyrics: false) == .close)
    }

    // MARK: Queue sections

    @Test func autoplaysSongsFollowTheListenersUnderContinuePlaying() {
        let upcoming = [4, 5, 6, 7, 8]
        let split = MiniPlayerQueueSections.split(upcoming, queueIndex: { $0 }, autoplayStart: 7)
        #expect(split.requested == [4, 5, 6])
        #expect(split.autoplay == [7, 8])
        #expect(!MiniPlayerQueueSections.headingIsContinuePlaying(requestedCount: 3, autoplayCount: 2))
        // Without Autoplay's songs, everything is Playing Next.
        let plain = MiniPlayerQueueSections.split(upcoming, queueIndex: { $0 }, autoplayStart: nil)
        #expect(plain.requested == upcoming && plain.autoplay.isEmpty)
        // Once only Autoplay's are left, the heading is Continue Playing.
        let onlyAutoplay = MiniPlayerQueueSections.split(upcoming, queueIndex: { $0 }, autoplayStart: 2)
        #expect(onlyAutoplay.requested.isEmpty)
        #expect(MiniPlayerQueueSections.headingIsContinuePlaying(requestedCount: 0, autoplayCount: 5))
        #expect(!MiniPlayerQueueSections.headingIsContinuePlaying(requestedCount: 0, autoplayCount: 0))
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

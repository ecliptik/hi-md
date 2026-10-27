import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

/// Whether lyrics carry timings the views can follow.
@Suite("Lyrics timing")
struct LyricsTimingTests {
    private static func record(plain: String?, synced: String?, instrumental: Bool = false) -> LRCLIBLyricsRecord {
        LRCLIBLyricsRecord(id: 1, trackName: "Dirty", artistName: "KMFDM", albumName: "Angst", duration: 226,
                           instrumental: instrumental, plainLyrics: plain, syncedLyrics: synced)
    }

    @Test func lrcWithTimestampsIsTimed() throws {
        let lrc = "[00:12.00]First line\n[00:15.50]Second line\n[00:19.20]Third line"
        let list = try #require(LyricsService.lyricsList(from: Self.record(plain: nil, synced: lrc)))
        let synced = try #require(list.structuredLyrics.first)
        #expect(synced.isTimed)
    }

    @Test func plainTextIsUntimedAndKeepsItsStanzas() throws {
        let plain = "Dirty, dirty\nDirty, dirty\n\n\nSecond verse\r\nStill second\n"
        let list = try #require(LyricsService.lyricsList(from: Self.record(plain: plain, synced: nil)))
        let entry = try #require(list.structuredLyrics.first)
        #expect(!entry.isTimed)
        #expect(!entry.synced)
        #expect(entry.line.map(\.value) == ["Dirty, dirty", "Dirty, dirty", "", "Second verse", "Still second"])
    }

    @Test func allZeroTimestampsAreUntimed() {
        let lyrics = StructuredLyrics(lang: "und", synced: true,
                                      line: (0..<8).map { Line(value: "Line \($0)", start: 0) })
        #expect(!lyrics.isTimed)
    }

    @Test func aSingleTimestampedLineIsUntimed() {
        let lyrics = StructuredLyrics(lang: "und", synced: true, line: [
            Line(value: "Intro", start: 12_000), Line(value: "Verse"), Line(value: "Chorus"),
        ])
        #expect(!lyrics.isTimed)
        #expect(!StructuredLyrics(lang: "und", synced: true, line: [Line(value: "Only", start: 5_000)]).isTimed)
    }

    @Test func syncedFlagWithoutStartTimesIsUntimed() {
        let lyrics = StructuredLyrics(lang: "en", synced: true, line: [Line(value: "One"), Line(value: "Two")])
        #expect(!lyrics.isTimed)
    }

    @Test func twoIncreasingStartsAreTimedEvenFromZero() {
        #expect(LyricsTiming.isTimed(starts: [0, 1_000]))
        #expect(LyricsTiming.isTimed(starts: [nil, 4_000, nil, 9_000]))
        #expect(!LyricsTiming.isTimed(starts: [3_000, 3_000, 3_000]))
        #expect(!LyricsTiming.isTimed(starts: []))
    }

    @Test func stanzasCollapseBlankRunsAndTrimTheEdges() {
        let stanzas = LyricsTiming.stanzas(from: ["", "  One  ", "Two", "", " ", "", "Three\nFour", ""])
        #expect(stanzas == ["One\nTwo", "Three\nFour"])
        #expect(LyricsTiming.stanzas(from: ["Windows\r\nlines"]) == ["Windows\nlines"])
    }
}

/// Untimed lyrics read as plain text: the view model never follows the song or seeks.
@Suite("LyricsViewModel — untimed lyrics")
@MainActor
struct LyricsViewModelUntimedTests {
    private static func loaded(_ lines: [Line], synced: Bool = false, position: TimeInterval = 0,
                               isPlaying: Bool = false) async throws -> (LyricsViewModel, PlayerState, MockPlayerService) {
        let serverID = UUID()
        let container = try ModelContainer(for: Schema([CachedLyrics.self]),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let list = LyricsList(structuredLyrics: [StructuredLyrics(lang: "und", synced: synced, line: lines)])
        let context = ModelContext(container)
        context.insert(CachedLyrics(songId: "song-1", serverId: serverID, jsonPayload: try JSONEncoder().encode(list)))
        try context.save()
        let player = MockPlayerService()
        let state = PlayerState()
        state.position = position
        if isPlaying { state.playbackState = .playing }
        let vm = LyricsViewModel(track: LyricsScrubbingFixtures.song(id: "song-1"), serverId: serverID,
                                 source: .navidrome,
                                 lyricsService: LyricsService(serverService: MockLyricsServerService(), modelContainer: container),
                                 playerService: player, playerState: state)
        await vm.load()
        return (vm, state, player)
    }

    private static let plain = ["Dirty, dirty", "Dirty, dirty", "", "Second verse"].map { Line(value: $0) }
    private static let zeroStamped = (0..<6).map { Line(value: "Line \($0)", start: 0) }

    @Test func plainLyricsShowTheNote() async throws {
        let (vm, _, _) = try await Self.loaded(Self.plain)
        #expect(!vm.isTimed)
        let note = try #require(vm.untimedNote)
        #expect(note.key == "Lyrics aren't timed for this song")
    }

    @Test func timedLyricsHaveNoNote() async throws {
        let (vm, _, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        #expect(vm.isTimed)
        #expect(vm.untimedNote == nil)
    }

    @Test func lrclibsInstrumentalLineHasNoNote() async throws {
        let (vm, _, _) = try await Self.loaded([Line(value: String(localized: "Instrumental"))])
        #expect(!vm.isTimed)
        #expect(vm.untimedNote == nil)
    }

    @Test func untimedLyricsNeverHighlightOrScroll() async throws {
        let (vm, _, _) = try await Self.loaded(Self.zeroStamped, synced: true, position: 30)
        vm.syncToPlayback()
        vm.update(elapsedMs: 30_000)
        #expect(vm.currentLineIndex == nil)
        #expect(vm.scrollRequest == nil)
    }

    @Test func untimedLyricsDontTrackPlayback() async throws {
        let (vm, _, _) = try await Self.loaded(Self.plain, isPlaying: true)
        vm.setVisible(true)
        #expect(!vm.isTrackingPlayback)
        vm.setVisible(false)
    }

    @Test func scrubbingMovesNothing() async throws {
        let (vm, state, _) = try await Self.loaded(Self.zeroStamped, synced: true)
        vm.userStartedScrolling()
        state.noteScrub(to: 42)
        vm.lyricsClockChanged()
        state.noteSeek(to: 42)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == nil)
        #expect(vm.scrollRequest == nil)
    }

    @Test func tappingALineDoesNotSeek() async throws {
        let (vm, state, player) = try await Self.loaded(Self.zeroStamped, synced: true)
        vm.userTapped(lineIndex: 3)
        try await Task.sleep(for: .milliseconds(50))
        #expect(player.seekCalledWith == nil)
        #expect(state.lyricsClock.isIdle)
    }
}

/// Untimed lyrics' sizes and the note's contrast on every surface.
@Suite("Untimed lyrics presentation")
struct UntimedLyricsPresentationTests {
    @Test func macNowPlayingReadsAt17To22Points() throws {
        for width in stride(from: 200.0, through: 1_400, by: 50) {
            let size = try #require(LyricsTypography.scaled(forWidth: width).plainSize)
            #expect((17...22).contains(size), "width \(width)")
        }
        #expect(LyricsTypography.scaled(forWidth: 424).plainSize == 18)
    }

    @Test func miniPlayerReadsAt15To17Points() throws {
        for width in stride(from: 200.0, through: 900, by: 50) {
            let typography = LyricsTypography.scaled(forWidth: width, minimum: 18, maximum: 28,
                                                     plainMinimum: 15, plainMaximum: 17)
                .withoutHeaderButtons().withDepth(.gentle)
            let size = try #require(typography.plainSize)
            #expect((15...17).contains(size), "width \(width)")
        }
    }

    @Test func mainWindowPanelUsesSystemColoursAt15Points() {
        #expect(LyricsTypography.mainWindowPanel.plainSize == 15)
        #expect(LyricsTypography.mainWindowPanel.usesSystemColors)
        #expect(!LyricsTypography.mainWindowPanel.showsHeaderButtons)
        // The synced lines there stay as they were.
        #expect(LyricsTypography.mainWindowPanel.lineSize == LyricsTypography.iPhone.lineSize)
        #expect(LyricsTypography.iPhone.plainSize == nil)
    }

    @Test func macFullScreenReadsAt24To30Points() {
        for width in stride(from: 900.0, through: 3_000, by: 100) {
            let metrics = FullScreenLyricsMetrics(width: width, height: width * 0.6)
            #expect((24...30).contains(metrics.plainLineSize), "width \(width)")
            #expect(LyricsTypography.fullScreen(metrics).plainSize == metrics.plainLineSize)
            #expect(metrics.plainLineSize < metrics.lineSize)
        }
    }

    @Test func spacingKeepsStanzasApartAndTheNoteSmall() {
        let metrics = UntimedLyricsMetrics(textSize: 17)
        #expect(metrics.stanzaSpacing > metrics.lineSpacing)
        #expect(metrics.noteSize < metrics.textSize)
        #expect((12...17).contains(UntimedLyricsMetrics(textSize: 30).noteSize))
        #expect((12...17).contains(UntimedLyricsMetrics(textSize: 15).noteSize))
    }

    /// The note is small text, so it needs 4.5:1: over the player backdrop's brightest stop, the
    /// karaoke view's brightest backdrop and the Mac full-screen lyrics' wash.
    @Test func theNoteReachesAAOverThePlayerBackdrops() {
        let opacity = UntimedLyricsPalette.noteOpacity
        #expect(NowPlayingText.contrastOfWhite(opacity: opacity,
                                               backgroundLuminance: PlayerBackgroundPalette.maxLuminance) >= 4.5)
        let karaoke = WCAGContrast.RGB.white.scaled(by: 0.55 * (1 - 0.45))
        #expect(WCAGContrast.ratio(WCAGContrast.RGB.white.composited(over: karaoke, opacity: opacity), karaoke) >= 4.5)
        let steps = (0...12).map { Double($0) / 12 }
        let washed = steps.flatMap { r in steps.flatMap { g in steps.map { b in
            FullScreenLyricsBackdrop.vivid(WCAGContrast.RGB(red: r, green: g, blue: b))
                .scaled(by: 1 - FullScreenLyricsBackdrop.lyricsWashOpacity)
        } } }
        for background in washed {
            #expect(WCAGContrast.ratio(WCAGContrast.RGB.white.composited(over: background, opacity: opacity),
                                       background) >= 4.5)
        }
    }
}

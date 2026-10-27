import Foundation
import SwiftData
import SwiftSonic
import Testing
import UIKit
@testable import Minidisc

/// Follow Lyrics: off, the lyrics never scroll by themselves; on, they follow the song.
@Suite("LyricsViewModel — Follow Lyrics")
@MainActor
struct LyricsFollowTests {
    /// Twenty synced lines, one a second, for `songID`, loaded over `state`.
    private static func loaded(songID: String = "song-1", state: PlayerState) async throws -> LyricsViewModel {
        let serverID = UUID()
        let container = try ModelContainer(for: Schema([CachedLyrics.self]),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let lines = (0..<20).map { Line(value: "Line \($0)", start: $0 * 1000) }
        let list = LyricsList(structuredLyrics: [StructuredLyrics(lang: "en", synced: true, line: lines)])
        let context = ModelContext(container)
        context.insert(CachedLyrics(songId: songID, serverId: serverID, jsonPayload: try JSONEncoder().encode(list)))
        try context.save()
        let vm = LyricsViewModel(track: LyricsScrubbingFixtures.song(id: songID), serverId: serverID, source: .navidrome,
                                 lyricsService: LyricsService(serverService: MockLyricsServerService(), modelContainer: container),
                                 playerService: MockPlayerService(), playerState: state)
        await vm.load()
        return vm
    }

    /// Playback ticks through lines 1 to 14.
    private static func play(_ vm: LyricsViewModel, _ state: PlayerState, through last: Int = 14) {
        for line in 1...last {
            state.position = Double(line) + 0.5
            vm.syncToPlayback()
        }
    }

    @Test func offNoTickScrolls() async throws {
        let state = PlayerState()
        let vm = try await Self.loaded(state: state)
        vm.autoScrollEnabled = false
        let opening = vm.scrollRequest
        Self.play(vm, state)
        // The line being sung still moves; the view doesn't.
        #expect(vm.currentLineIndex == 14)
        #expect(vm.scrollRequest == opening)
        #expect(!vm.autoScrollEnabled)
    }

    @Test func onEveryLineScrolls() async throws {
        let state = PlayerState()
        let vm = try await Self.loaded(state: state)
        #expect(vm.autoScrollEnabled)
        var revisions: [Int] = []
        for line in 1...5 {
            state.position = Double(line) + 0.5
            vm.syncToPlayback()
            #expect(vm.scrollRequest?.index == line)
            revisions.append(vm.scrollRequest?.revision ?? -1)
        }
        #expect(Set(revisions).count == 5)
    }

    @Test func aScrubOrSeekTurnsItBackOn() async throws {
        let state = PlayerState()
        let vm = try await Self.loaded(state: state)
        vm.autoScrollEnabled = false
        state.noteScrub(to: 6.5)
        vm.lyricsClockChanged()
        #expect(vm.autoScrollEnabled)
        #expect(state.followsLyrics)
        #expect(vm.scrollRequest?.index == 6)

        vm.autoScrollEnabled = false
        state.noteSeek(to: 12.2)
        vm.lyricsClockChanged()
        #expect(vm.autoScrollEnabled)
        #expect(vm.scrollRequest?.index == 12)
    }

    @Test func togglingOnScrollsOnceThenFollows() async throws {
        let state = PlayerState()
        let vm = try await Self.loaded(state: state)
        vm.autoScrollEnabled = false
        Self.play(vm, state, through: 8)
        let before = vm.scrollRequest?.revision ?? 0
        vm.autoScrollEnabled = true
        #expect(vm.scrollRequest?.index == 8)
        #expect(vm.scrollRequest?.animated == false)
        #expect(vm.scrollRequest?.revision == before &+ 1)
        // Once: the same line again, or turning it on again, asks for nothing more.
        vm.syncToPlayback()
        vm.autoScrollEnabled = true
        #expect(vm.scrollRequest?.revision == before &+ 1)
        // And it follows from there.
        state.position = 9.5
        vm.syncToPlayback()
        #expect(vm.scrollRequest?.index == 9)
    }

    @Test func turningItOnEndsAPauseForTheListenersScroll() async throws {
        let state = PlayerState()
        let vm = try await Self.loaded(state: state)
        vm.autoScrollEnabled = false
        vm.userStartedScrolling()
        vm.autoScrollEnabled = true
        #expect(!vm.isUserScrolling)
    }

    @Test func offHoldsAcrossSongsAndEveryLyricsView() async throws {
        let state = PlayerState()
        let first = try await Self.loaded(songID: "song-1", state: state)
        first.autoScrollEnabled = false
        // The next song's lyrics, and another view's, get a view model of their own.
        state.currentTrack = LyricsScrubbingFixtures.song(id: "song-2")
        let next = try await Self.loaded(songID: "song-2", state: state)
        let opening = next.scrollRequest
        #expect(!next.autoScrollEnabled)
        Self.play(next, state)
        #expect(next.scrollRequest == opening)
        // Turned on in one view, it's on in the other.
        next.autoScrollEnabled = true
        #expect(first.autoScrollEnabled)
    }
}

/// Follow Lyrics' symbol: the Maps follow arrow, filled while on.
@Suite("Follow Lyrics symbol")
struct FollowLyricsSymbolTests {
    @Test func onIsTheFilledArrowAndOffItsOutline() {
        #expect(FollowLyricsSymbol.name(isOn: true) == "location.fill")
        #expect(FollowLyricsSymbol.name(isOn: false) == "location")
        #expect(FollowLyricsSymbol.on == FollowLyricsSymbol.off + ".fill")
    }

    @Test(arguments: [FollowLyricsSymbol.on, FollowLyricsSymbol.off])
    func theSymbolsExist(_ name: String) {
        #expect(UIImage(systemName: name) != nil)
    }

    @Test func theLabelsAreTranslated() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Minidisc/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        for key in ["Follow", "Follow Lyrics"] {
            let entry = try #require(strings[key] as? [String: Any], "\(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "\(key)")
            for language in ["de", "el", "es", "fr", "it", "ja", "zh-Hans", "zh-Hant"] {
                #expect(localizations[language] != nil, "\(key) \(language)")
            }
        }
    }
}

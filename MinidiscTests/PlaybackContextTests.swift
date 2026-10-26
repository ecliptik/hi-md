import AVFoundation
import Foundation
import SwiftData
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

// MARK: - Test doubles

private nonisolated final class ContextTestEngine: AudioEngine, Sendable {
    private struct Storage {
        var delegate: AudioEngineDelegate?
        var plays: UInt64 = 0
        var volume: Float = 1
    }
    private let storage = Mutex(Storage())
    var delegate: AudioEngineDelegate? {
        get { storage.withLock { $0.delegate } }
        set { storage.withLock { $0.delegate = newValue } }
    }
    func play(trackID: String, url: URL, headers: [String: String]) -> AudioEnginePlaybackToken {
        let token = storage.withLock { $0.plays += 1; return AudioEnginePlaybackToken(rawValue: $0.plays) }
        delegate?.audioEngineDidChangeState(.buffering, playbackToken: token)
        return token
    }
    func pause() {}
    func resume() {}
    func stop() {}
    func resetAfterMediaServicesReset() {}
    func seek(to seconds: Double) async -> Bool { true }
    var volume: Float {
        get { storage.withLock { $0.volume } }
        set { storage.withLock { $0.volume = newValue } }
    }
    var progress: Double { 0 }
    var duration: Double { 120 }
    var isSeekable: Bool { true }
    var isReady: Bool { true }
    func applyReplayGain(dB: Float) {}
    func preloadNext(trackID: String, url: URL, headers: [String: String], crossfadeDuration: Double,
                     leadInTrim: Double, replayGainDB: Float, expectedCurrentTrackID: String) {}
    func cancelPreload() {}
    func setTrackEndTrim(_ seconds: Double, expectedCurrentTrackID: String) {}
    func setTrackDuration(_ seconds: Double) {}
}

private nonisolated final class ContextTestAudioSession: AudioSessionControlling {
    var outputs: [AudioRouteOutputSnapshot] { [AudioRouteOutputSnapshot(uid: "speaker", portType: .builtInSpeaker)] }
    func activate() throws {}
    func deactivate() {}
    func invalidateConfiguration() {}
}

private actor ContextTestResolver: MediaResolverProtocol {
    func localSource(songId: String, serverId: UUID) async -> MediaSource? { nil }
    func resolve(songId: String, serverId: UUID) async throws -> MediaSource {
        .stream(URL(string: "https://playback.invalid/stream/\(songId)")!, customHeaders: [:])
    }
    func resolveRadio(_ station: InternetRadioStation) async throws -> MediaSource { throw MinidiscError.notImplemented }
    func availability(songId: String, serverId: UUID) async -> MediaAvailability { .unknown }
}

/// Smart Shuffle and Instant Mix results the tests choose; auto-extend draws on the backfill.
private nonisolated final class ContextTestLibrary: AlbumBrowsing, ArtistBrowsing, PlaybackQueueBuilding, PlaybackReporting {
    private struct Storage {
        var smartShuffle: [DisplayableSong] = []
        var mix: [DisplayableSong] = []
        var backfill: [DisplayableSong] = []
    }
    private let storage = Mutex(Storage())
    func setSmartShuffle(_ songs: [DisplayableSong]) { storage.withLock { $0.smartShuffle = songs } }
    func setMix(_ songs: [DisplayableSong]) { storage.withLock { $0.mix = songs } }
    func setBackfill(_ songs: [DisplayableSong]) { storage.withLock { $0.backfill = songs } }

    func album(id: String) async throws -> AlbumID3 { throw MinidiscError.notImplemented }
    func allAlbums() async throws -> [AlbumID3] { [] }
    func artists() async throws -> [ArtistIndex] { [] }
    func artist(id: String) async throws -> ArtistID3 { throw MinidiscError.notImplemented }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { [] }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { storage.withLock { $0.smartShuffle } }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] {
        storage.withLock { $0.backfill }.filter { !excludedIds.contains($0.id) }
    }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { storage.withLock { $0.mix } }
    func scrobble(songId: String, submission: Bool) async {}
}

@MainActor
private struct ContextListenBrainzTransport: ListenBrainzTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.unsupportedURL) }
}

private nonisolated func song(_ id: String) -> DisplayableSong {
    DisplayableSong(id: id, title: "Song \(id)", artist: "Artist", albumId: "album-1", albumName: "Album",
                    artistId: "artist-1", genre: nil, duration: 120, trackNumber: nil, isDownloaded: false,
                    coverArtId: nil, audioFormat: nil, replayGainTrackGain: nil, replayGainTrackPeak: nil,
                    replayGainAlbumGain: nil, replayGainAlbumPeak: nil, replayGainBaseGain: nil,
                    replayGainFallbackGain: nil)
}

private nonisolated func songs(_ ids: String...) -> [DisplayableSong] { ids.map(song) }

@MainActor
private struct ContextHarness {
    let player: PlayerService
    let state = PlayerState()
    let library = ContextTestLibrary()
    let sessionService: PlaybackSessionService

    init(sessionContainer: ModelContainer? = nil) throws {
        let container = try ModelContainer.minidisc(inMemory: true)
        let defaults = UserDefaults(suiteName: "playback-context.\(UUID())")!
        let server = MockServerService()
        server.state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "Test", baseURL: "https://playback.invalid", username: "test"
        ))
        let toast = ToastService()
        let crossfade = CrossfadeSettings(defaults: defaults)
        sessionService = PlaybackSessionService(modelContainer: try sessionContainer ?? ModelContainer.session(inMemory: true))
        player = PlayerService(
            state: state,
            mediaResolver: ContextTestResolver(),
            serverService: server,
            sessionService: sessionService,
            artworkImageCache: ArtworkImageCache(
                coverArtURLProvider: { _, _ in nil },
                dataLoader: { _ in throw URLError(.unsupportedURL) },
                imageDecoder: { _, _ in nil }
            ),
            libraryService: library,
            audioStreamCache: MockAudioStreamCache(),
            downloadService: DownloadService(serverService: server, modelContainer: container, toastService: toast),
            cacheSettings: CacheSettings(defaults: defaults),
            playbackPreferences: PlaybackPreferences(defaults: defaults),
            replayGainSettings: ReplayGainSettings(defaults: defaults),
            crossfadeSettings: crossfade,
            initialCrossfadeConfig: crossfade.config,
            toastService: toast,
            statsService: StatsService(modelContainer: container),
            listenBrainzService: ListenBrainzService(
                client: ListenBrainzClient(transport: ContextListenBrainzTransport()),
                keychain: MockKeychain(), userDefaults: UserDefaults(suiteName: "playback-context-lb.\(UUID())")!,
                queueFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
            ),
            playbackDiagnostics: PlaybackDiagnostics(capacity: 100),
            engine: ContextTestEngine(),
            // Long graces keep network recovery from rebuilding items while a test runs.
            networkRecoveryTiming: .init(
                startupGrace: .seconds(30), stallGrace: .seconds(30),
                retryDelay: .seconds(30), validationDelay: .seconds(30),
                prefetchRetryDelay: .seconds(30), downloadRetryDelay: .seconds(30),
                dataFlowingGrace: .seconds(30), dataFlowRecheck: .seconds(30)
            ),
            audioSession: ContextTestAudioSession()
        )
    }

    func waitUntil(_ what: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Timed out waiting for \(what)")
    }
}

private let station = PlaybackContext.artistStation(artistId: "artist-1", artistName: "DJ Shadow")
private let album = PlaybackContext.album(id: "album-1", name: "Endtroducing.....", coverArtId: "al-1")

// MARK: - Model

@Suite("Playback context — model")
struct PlaybackContextModelTests {
    @Test("Each source has a title and a symbol, and only openable sources have a destination")
    func presentation() {
        #expect(station.title == "DJ Shadow Station")
        #expect(station.symbolName == "dot.radiowaves.left.and.right")
        #expect(station.destination == .artist(id: "artist-1", name: "DJ Shadow"))
        #expect(PlaybackContext.smartShuffle.title == "Smart Shuffle")
        #expect(PlaybackContext.smartShuffle.symbolName == "sparkles")
        #expect(PlaybackContext.smartShuffle.destination == nil)
        #expect(album.title == "Endtroducing.....")
        #expect(album.symbolName == "square.stack")
        #expect(album.destination == .album(id: "album-1", name: "Endtroducing.....", coverArtId: "al-1"))
        let songMix = PlaybackContext.instantMix(seed: .song, id: "s1", name: "Midnight City")
        #expect(songMix.title == "Midnight City Mix")
        #expect(songMix.destination == nil)
        #expect(PlaybackContext.instantMix(seed: .album, id: "al", name: "Hurry Up").destination
                == .album(id: "al", name: "Hurry Up", coverArtId: nil))
        #expect(PlaybackContext.internetRadio(name: "FIP").destination == nil)
        #expect(station.accessibilityLabel == "Playing from DJ Shadow Station")
        #expect(station.queueHeader == "Playing Next from DJ Shadow Station")
    }

    @Test("Mood and Wrapped playlists are recognised by the names Minidisc gives them")
    func playlistRecognition() {
        #expect(PlaybackContext.forPlaylist(id: "p1", name: Mood.chill.playlistName, coverArtId: nil)
                == .mood(.chill, playlistId: "p1"))
        let wrapped = PlaybackContext.forPlaylist(id: "p2", name: "Minidisc Wrapped 2025", coverArtId: nil)
        #expect(wrapped == .wrapped(year: 2025, playlistId: "p2"))
        #expect(wrapped.destination == .playlist(id: "p2", name: "Minidisc Wrapped 2025", coverArtId: nil))
        #expect(PlaybackContext.mood(.night, playlistId: "p3").symbolName == Mood.night.symbolName)
        #expect(PlaybackContext.forPlaylist(id: "p4", name: "Road Trip", coverArtId: "c")
                == .playlist(id: "p4", name: "Road Trip", coverArtId: "c"))
    }

    @Test("Every context survives encoding, and an unknown one decodes as nil")
    func codableRoundTrip() throws {
        let all: [PlaybackContext] = [
            station, .smartShuffle, .instantMix(seed: .song, id: "s", name: "S"), album,
            .playlist(id: "p", name: "P", coverArtId: nil), .mood(.focus, playlistId: "m"),
            .wrapped(year: 2024, playlistId: "w"), .internetRadio(name: "FIP"),
        ]
        for context in all {
            let data = try JSONEncoder().encode(context)
            #expect(try JSONDecoder().decode(PlaybackContext.self, from: data) == context)
        }
        let future = PlaybackSessionContext(contextData: Data(#"{"concert":{"venue":"Fillmore"}}"#.utf8))
        #expect(future.decodedContext() == nil)
    }
}

// MARK: - Session persistence

@Suite("Playback context — session persistence")
struct PlaybackContextSessionTests {
    private func payload(_ context: PlaybackContext?) -> SessionPayload {
        let queue = songs("a", "b")
        return SessionPayload(currentIndex: 0, currentPosition: 0, queue: queue, currentTrack: queue[0],
                              repeatMode: .off, queueRevision: nil, context: context)
    }

    @Test("The context is saved and restored with the session, and replaced or removed with it")
    func roundTrip() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        await service.save(playerState: payload(station))
        #expect(try #require(await service.loadRestoredSession()).context == station)
        await service.save(playerState: payload(.smartShuffle))
        #expect(try #require(await service.loadRestoredSession()).context == .smartShuffle)
        await service.save(playerState: payload(nil))
        #expect(try #require(await service.loadRestoredSession()).context == nil)
        await service.save(playerState: payload(album))
        await service.clear()
        await service.save(playerState: payload(nil))
        #expect(try #require(await service.loadRestoredSession()).context == nil)
    }

    @Test("A session saved before contexts existed restores with none")
    func sessionWithoutContextRow() async throws {
        let container = try ModelContainer.session(inMemory: true)
        // What an older build wrote: the session row alone.
        let context = ModelContext(container)
        let queue = songs("a", "b")
        context.insert(PlaybackSession(currentIndex: 1, currentPosition: 12, queue: queue, currentTrack: queue[1]))
        try context.save()
        let restored = try #require(await PlaybackSessionService(modelContainer: container).loadRestoredSession())
        #expect(restored.queue.map(\.id) == ["a", "b"])
        #expect(restored.currentIndex == 1)
        #expect(restored.context == nil)
    }
}

// MARK: - Player lifetime

@Suite("Playback context — player lifetime", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct PlaybackContextPlayerTests {
    @Test("A station keeps its context through the Instant Mix fill and auto-extend")
    func stationSurvivesFillAndAutoExtend() async throws {
        let h = try ContextHarness()
        h.library.setMix(songs("m1", "m2", "m3"))
        h.library.setBackfill(songs("x1", "x2"))
        try await h.player.playInstantMix(from: .artist(id: "artist-1"), startingWith: song("seed"), context: station)
        #expect(h.state.playbackContext == station)
        try await h.waitUntil("the mix fill") { h.state.queue.map(\.id) == ["seed", "m1", "m2", "m3"] }
        #expect(h.state.playbackContext == station)

        await h.player.setAutoExtendEnabled(true)
        try await h.waitUntil("auto-extend") { h.state.queue.contains { $0.id == "x1" } }
        #expect(h.state.originalQueueEndIndex == 4)
        #expect(h.state.playbackContext == station)
        #expect(!h.state.isSmartShuffleActive)
        await h.player.stop()
    }

    @Test("A mix built before it plays starts with its context")
    func mixWithoutSeedTrack() async throws {
        let h = try ContextHarness()
        h.library.setMix(songs("m1", "m2"))
        let mix = PlaybackContext.instantMix(seed: .song, id: "s1", name: "Teardrop")
        try await h.player.playInstantMix(from: .song(id: "s1"), startingWith: nil, context: mix)
        #expect(h.state.queue.map(\.id) == ["m1", "m2"])
        #expect(h.state.playbackContext == mix)
        await h.player.stop()
    }

    @Test("Skips and queue edits keep the context; a new queue without one clears it")
    func keepAndClear() async throws {
        let h = try ContextHarness()
        try await h.player.play(tracks: songs("a", "b", "c"), startIndex: 0, context: album)
        #expect(h.state.playbackContext == album)

        try await h.player.skipToNext()
        #expect(h.state.currentTrack?.id == "b")
        // The same queue again (a skip from elsewhere) is not a new queue.
        try await h.player.play(tracks: h.state.queue, startIndex: 2)
        await h.player.addToQueue(song("d"))
        await h.player.playNext(song("e"))
        await h.player.moveInQueue(fromIndex: 3, toIndex: 4)
        await h.player.removeFromQueue(at: 0)
        await h.player.toggleShuffle()
        #expect(h.state.playbackContext == album)

        try await h.player.play(tracks: songs("z"), startIndex: 0)
        #expect(h.state.playbackContext == nil)
        await h.player.stop()
    }

    @Test("Playing a different source replaces the context, and Stop clears it")
    func replaceAndStop() async throws {
        let h = try ContextHarness()
        try await h.player.play(tracks: songs("a", "b"), startIndex: 0, context: album)
        let playlist = PlaybackContext.playlist(id: "p", name: "Road Trip", coverArtId: nil)
        try await h.player.play(tracks: songs("a", "b"), startIndex: 0, context: playlist)
        #expect(h.state.playbackContext == playlist)
        try await h.player.play(preparingQueue: {
            PreparedPlaybackQueue(tracks: songs("c", "d"), startIndex: 1, context: .mood(.focus, playlistId: "m"))
        })
        #expect(h.state.playbackContext == .mood(.focus, playlistId: "m"))
        await h.player.stop()
        #expect(h.state.playbackContext == nil)
    }

    @Test("Smart Shuffle sets its context and the queue badge, and a new play ends both")
    func smartShuffle() async throws {
        let h = try ContextHarness()
        h.library.setSmartShuffle(songs("r1", "r2", "r3"))
        try await h.player.playSmartShuffle()
        #expect(h.state.playbackContext == .smartShuffle)
        #expect(h.state.isSmartShuffleActive)
        #expect(h.state.queueModeBadge == "sparkles")
        try await h.player.skipToNext()
        #expect(h.state.isSmartShuffleActive)

        try await h.player.play(tracks: songs("a"), startIndex: 0)
        #expect(!h.state.isSmartShuffleActive)
        #expect(h.state.queueModeBadge == nil)
        await h.player.stop()
    }

    @Test("The context is restored with the saved session")
    func sessionRestore() async throws {
        let sessionContainer = try ModelContainer.session(inMemory: true)
        let first = try ContextHarness(sessionContainer: sessionContainer)
        try await first.player.playInstantMix(from: .artist(id: "artist-1"), startingWith: song("seed"), context: station)
        // play() saves the session once the queue is committed.
        let saved = try #require(await first.sessionService.loadRestoredSession())
        #expect(saved.context == station)

        let relaunched = try ContextHarness(sessionContainer: sessionContainer)
        await relaunched.player.restoreSession()
        #expect(relaunched.state.currentTrack?.id == "seed")
        #expect(relaunched.state.playbackContext == station)
        await first.player.stop()
    }
}

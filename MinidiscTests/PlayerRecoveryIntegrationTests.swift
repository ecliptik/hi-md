import AVFoundation
import Foundation
import SwiftData
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

private nonisolated final class RecoveryTestEngine: AudioEngine, Sendable {
    private struct Storage {
        var delegate: AudioEngineDelegate?
        var plays = 0
        var stops = 0
        var resets = 0
        var poisoned = false
        var active = false
        var volume: Float = 1
        var playingSince: Date?
        var position: Double = 0
        var failNextSeek = false
        var sourceURL: URL?
        var preloads: [(trackID: String, expectedCurrentTrackID: String)] = []
        var buffered: Double = 0
    }
    private let storage = Mutex(Storage())
    var delegate: AudioEngineDelegate? {
        get { storage.withLock { $0.delegate } }
        set { storage.withLock { $0.delegate = newValue } }
    }
    var playCount: Int { storage.withLock { $0.plays } }
    var sourceURL: URL? { storage.withLock { $0.sourceURL } }
    var stopCount: Int { storage.withLock { $0.stops } }
    var resetCount: Int { storage.withLock { $0.resets } }
    func poisonMediaServices() { storage.withLock { $0.poisoned = true; $0.playingSince = nil } }
    var token: AudioEnginePlaybackToken { .init(rawValue: UInt64(playCount)) }
    func play(trackID: String, url: URL, headers: [String: String]) -> AudioEnginePlaybackToken {
        storage.withLock {
            $0.plays += 1
            $0.sourceURL = url
            $0.active = true
            $0.playingSince = nil
            $0.position = 0
            $0.buffered = 0
        }
        let token = token
        delegate?.audioEngineDidChangeState(.paused, playbackToken: token)
        delegate?.audioEngineDidChangeState(.buffering, playbackToken: token)
        return token
    }
    func startAdvancing() { storage.withLock { if !$0.poisoned { $0.playingSince = Date() } } }
    /// Data arriving while playback waits.
    func receiveData(seconds: Double) { storage.withLock { $0.buffered += seconds } }
    var bufferedDuration: TimeInterval { storage.withLock { $0.buffered } }
    func pause() { storage.withLock { $0.playingSince = nil } }
    func resume() {}
    func stop() { storage.withLock { $0.stops += 1; $0.active = false; $0.playingSince = nil } }
    func resetAfterMediaServicesReset() {
        storage.withLock {
            $0.resets += 1
            $0.poisoned = false
            $0.active = false
            $0.playingSince = nil
            $0.position = 0
        }
    }
    func failNextSeek() { storage.withLock { $0.failNextSeek = true } }
    func seek(to seconds: Double) async -> Bool {
        storage.withLock {
            if $0.failNextSeek { $0.failNextSeek = false; return false }
            $0.position = seconds
            return true
        }
    }
    var volume: Float {
        get { storage.withLock { $0.volume } }
        set { storage.withLock { $0.volume = newValue } }
    }
    var progress: Double {
        storage.withLock { $0.position + ($0.playingSince.map { Date().timeIntervalSince($0) } ?? 0) }
    }
    var duration: Double { 120 }
    var isSeekable: Bool { true }
    var isReady: Bool { storage.withLock { !$0.active } }
    func applyReplayGain(dB: Float) {}
    func cancelPreload() {}
    func setTrackEndTrim(_ seconds: Double, expectedCurrentTrackID: String) {}
    func setTrackDuration(_ seconds: Double) {}
    /// Acts like AVPlayerEngine dropping a standby item that failed to load or preroll.
    func failStandby(trackID: String) { delegate?.audioEngineStandbyPreloadDidFail(trackID: trackID) }
    /// Standby preloads requested so far, as (track, track it follows).
    var preloads: [(trackID: String, expectedCurrentTrackID: String)] { storage.withLock { $0.preloads } }
    func preloadNext(
        trackID: String,
        url: URL,
        headers: [String: String],
        crossfadeDuration: Double,
        leadInTrim: Double,
        replayGainDB: Float,
        expectedCurrentTrackID: String
    ) {
        storage.withLock { $0.preloads.append((trackID, expectedCurrentTrackID)) }
    }
}

private nonisolated final class RecoveryTestAudioSession: AudioSessionControlling {
    static let headphones = AudioRouteOutputSnapshot(uid: "headphones", portType: .bluetoothA2DP)
    static let speaker = AudioRouteOutputSnapshot(uid: "speaker", portType: .builtInSpeaker)
    private struct Storage {
        var outputs = [RecoveryTestAudioSession.headphones]
        var activations = 0
        var deactivations = 0
        var invalidations = 0
        var failuresRemaining = 0
    }
    private let storage = Mutex(Storage())
    var outputs: [AudioRouteOutputSnapshot] {
        get { storage.withLock { $0.outputs } }
        set { storage.withLock { $0.outputs = newValue } }
    }
    var activations: Int { storage.withLock { $0.activations } }
    var invalidations: Int { storage.withLock { $0.invalidations } }
    var deactivations: Int { storage.withLock { $0.deactivations } }
    func failNextActivations(_ count: Int) { storage.withLock { $0.failuresRemaining = count } }
    func activate() throws {
        let shouldFail = storage.withLock {
            $0.activations += 1
            if $0.failuresRemaining > 0 { $0.failuresRemaining -= 1; return true }
            return false
        }
        if shouldFail { throw NSError(domain: NSOSStatusErrorDomain, code: -50) }
    }
    func deactivate() { storage.withLock { $0.deactivations += 1 } }
    func invalidateConfiguration() { storage.withLock { $0.invalidations += 1 } }
}

private actor RecoveryTestResolver: MediaResolverProtocol {
    var usesDownloadedSource = false
    var usesCachedSource = false
    func useCachedSource() { usesCachedSource = true }
    /// The cached copy is a lower-quality transcode than the stream, as after cellular caching.
    var cachedCopyIsLowerQuality = false
    func useLowerQualityCachedSource() { usesCachedSource = true; cachedCopyIsLowerQuality = true }
    func hasLocalCopy(songId: String, serverId: UUID, atLeast quality: CachedAudioQuality) async -> Bool {
        if usesDownloadedSource { return true }
        return usesCachedSource && !cachedCopyIsLowerQuality
    }
    func localSource(songId: String, serverId: UUID) async -> MediaSource? {
        if usesDownloadedSource { return .downloaded(URL(fileURLWithPath: "/tmp/recovery-test-audio.m4a")) }
        if usesCachedSource { return .cached(URL(fileURLWithPath: "/tmp/recovery-test-cache.m4a")) }
        return nil
    }
    func useDownloadedSource() { usesDownloadedSource = true }
    var missingIDs: Set<String> = []
    var blockAvailability = false
    var availabilityCalls = 0
    private var pending: CheckedContinuation<MediaAvailability, Never>?
    private var blockedResolutionID: String?
    private var pendingResolution: CheckedContinuation<Void, Never>?
    var isResolvingBlockedTrack: Bool { pendingResolution != nil }
    func blockResolution(of trackID: String) { blockedResolutionID = trackID }
    func releaseResolution() {
        blockedResolutionID = nil
        pendingResolution?.resume()
        pendingResolution = nil
    }
    func configure(missing: Set<String> = [], block: Bool = false) {
        missingIDs = missing
        blockAvailability = block
    }
    private(set) var resolveCalls: [String: Int] = [:]
    private var failuresRemaining: [String: Int] = [:]
    /// The next `count` resolutions of `trackID` throw a transient network error.
    func failResolutions(of trackID: String, count: Int) { failuresRemaining[trackID] = count }
    func resolve(songId: String, serverId: UUID) async throws -> MediaSource {
        resolveCalls[songId, default: 0] += 1
        if let remaining = failuresRemaining[songId], remaining > 0 {
            failuresRemaining[songId] = remaining - 1
            throw URLError(.timedOut)
        }
        if songId == blockedResolutionID {
            await withCheckedContinuation { pendingResolution = $0 }
        }
        if let local = await localSource(songId: songId, serverId: serverId) { return local }
        return .stream(URL(string: "https://playback.invalid/stream")!, customHeaders: [:])
    }
    func resolveRadio(_ station: InternetRadioStation) async throws -> MediaSource { throw MinidiscError.notImplemented }
    func availability(songId: String, serverId: UUID) async -> MediaAvailability {
        availabilityCalls += 1
        if blockAvailability {
            return await withCheckedContinuation { pending = $0 }
        }
        return missingIDs.contains(songId) ? .missing : .unknown
    }
    func releaseAvailability(_ result: MediaAvailability) {
        blockAvailability = false
        pending?.resume(returning: result)
        pending = nil
    }
}

private nonisolated final class RecoveryTestLibrary: AlbumBrowsing, ArtistBrowsing, PlaybackQueueBuilding, PlaybackReporting {
    func album(id: String) async throws -> AlbumID3 { throw MinidiscError.notImplemented }
    func allAlbums() async throws -> [AlbumID3] { [] }
    func artists() async throws -> [ArtistIndex] { [] }
    func artist(id: String) async throws -> ArtistID3 { throw MinidiscError.notImplemented }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { [] }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { [] }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { [] }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { [] }
    func scrobble(songId: String, submission: Bool) async {}
}

@MainActor
private struct RecoveryListenBrainzTransport: ListenBrainzTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.unsupportedURL)
    }
}

@MainActor
private struct RecoveryHarness {
    let player: PlayerService
    let state = PlayerState()
    let engine = RecoveryTestEngine()
    let audioSession = RecoveryTestAudioSession()
    let resolver = RecoveryTestResolver()
    let diagnostics = PlaybackDiagnostics(capacity: 500)
    let defaults = UserDefaults(suiteName: "playback-recovery.\(UUID())")!
    let server = MockServerService()

    init(
        startupGrace: Duration = .milliseconds(600),
        audioStartupGrace: Duration = .milliseconds(800),
        audioRetryDelay: Duration = .milliseconds(40),
        prefetchRetryDelay: Duration = .milliseconds(50),
        localMusicStore: LocalMusicStore? = nil,
        configureServer: Bool = true,
        audioStreamCache: (any AudioStreamCacheProtocol)? = nil,
        cacheSession: URLSession? = nil,
        streamCacheFormat: CacheFormat = .flacOriginal,
        stallGrace: Duration = .milliseconds(100),
        dataFlowingGrace: Duration = .milliseconds(600)
    ) throws {
        let container = try ModelContainer.minidisc(inMemory: true)
        server.state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "Test", baseURL: "https://playback.invalid", username: "test"
        ))
        if !configureServer { server.state.activeServer = nil }
        let toast = ToastService()
        let download = DownloadService(serverService: server, modelContainer: container, toastService: toast)
        let cacheSettings = CacheSettings(defaults: defaults)
        // The stub server cannot create background cache URLs; `.matchStream` downloads the stream URL.
        cacheSettings.cacheFormat = streamCacheFormat
        let crossfade = CrossfadeSettings(defaults: defaults)
        player = PlayerService(
            state: state,
            mediaResolver: resolver,
            serverService: server,
            sessionService: PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true)),
            artworkImageCache: ArtworkImageCache(
                coverArtURLProvider: { _, _ in nil },
                dataLoader: { _ in throw URLError(.unsupportedURL) },
                imageDecoder: { _, _ in nil }
            ),
            libraryService: RecoveryTestLibrary(),
            audioStreamCache: audioStreamCache ?? MockAudioStreamCache(),
            downloadService: download,
            cacheSettings: cacheSettings,
            playbackPreferences: PlaybackPreferences(defaults: defaults),
            replayGainSettings: ReplayGainSettings(defaults: defaults),
            crossfadeSettings: crossfade,
            initialCrossfadeConfig: crossfade.config,
            toastService: toast,
            statsService: StatsService(modelContainer: container),
            listenBrainzService: ListenBrainzService(
                client: ListenBrainzClient(transport: RecoveryListenBrainzTransport()),
                keychain: MockKeychain(), userDefaults: UserDefaults(suiteName: "playback-recovery-lb.\(UUID())")!,
                queueFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
            ),
            playbackDiagnostics: diagnostics,
            engine: engine,
            networkRecoveryTiming: .init(
                startupGrace: startupGrace, stallGrace: stallGrace,
                retryDelay: .milliseconds(40), validationDelay: .milliseconds(200),
                prefetchRetryDelay: prefetchRetryDelay,
                downloadRetryDelay: .milliseconds(20),
                dataFlowingGrace: dataFlowingGrace, dataFlowRecheck: .milliseconds(50)
            ),
            audioSession: audioSession,
            audioRecoveryTiming: .init(
                retryDelay: audioRetryDelay, routeGrace: .seconds(2),
                startupGrace: audioStartupGrace, pollInterval: .milliseconds(10)
            ),
            localMusicStore: localMusicStore,
            cacheSession: cacheSession
        )
    }

    func play(_ ids: [String] = ["a", "b"]) async throws {
        let tracks = try ids.map { id in
            DisplayableSong(from: try JSONDecoder().decode(Song.self, from: Data(
                "{\"id\":\"\(id)\",\"title\":\"Test\",\"isDir\":false,\"duration\":120}".utf8
            )))
        }
        try await player.play(tracks: tracks, startIndex: 0)
    }

    var report: String {
        diagnostics.makeReport(context: .init(
            appVersion: "test", appBuild: "0", operatingSystem: "test",
            playbackStatus: .init(state.playbackState), isPlaybackAvailable: true,
            networkPath: nil, connectionVersion: nil
        ))
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(6)
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await condition(), "\(report)\nEngine plays=\(engine.playCount) position=\(engine.progress)")
    }
}

@Suite("Player recovery integration", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct PlayerRecoveryIntegrationTests {
    @Test(arguments: [false, true])
    func stalledStreamUsesNewlyCompletedCacheWithoutServerProbe(offline: Bool) async throws {
        // Long enough that a busy MainActor can't let a startup probe rebuild from the stream URL
        // before the cached copy appears; the stall below uses the short stallGrace.
        let h = try RecoveryHarness(startupGrace: .seconds(2))
        try await h.play()
        try await h.waitUntil { h.report.contains("engine state=buffering") }
        _ = await h.engine.seek(to: 37)
        h.state.position = 37
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        // The track was remote at startup; its cache copy becomes available later.
        await h.resolver.useCachedSource()
        if offline {
            await h.player.handleNetworkPathChanged(NetworkPathEvent(
                generation: 1,
                descriptor: NetworkPathDescriptor(
                    isOnline: false, isExpensive: true, isConstrained: false,
                    supportsDNS: false, supportsIPv4: false, supportsIPv6: false,
                    interfaces: [.cellular], gateways: []
                )
            ))
        }
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        try await h.waitUntil { h.engine.playCount == 2 }
        try await h.waitUntil {
            h.report.components(separatedBy: "item-rebuilt").count > 1
        }
        #expect(h.engine.sourceURL?.lastPathComponent == "recovery-test-cache.m4a", "\(h.report)")
        #expect(await h.resolver.availabilityCalls == 0, "\(h.report)")
        #expect(h.state.position == 37)
        #expect(h.state.currentTrack?.id == "a")
        #expect(h.report.contains("playback source=cache"), "\(h.report)")
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        try await h.waitUntil { h.report.contains("progress-validated") }
        #expect(h.engine.progress >= 37)
        #expect(h.engine.volume > 0)
        await h.player.stop()
    }

    @Test(arguments: [false, true])
    func loadingReplacementKeepsTheResumePosition(downloaded: Bool) async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(3))
        if downloaded { await h.resolver.useDownloadedSource() }
        try await h.play()
        _ = await h.engine.seek(to: 37)
        h.state.position = 37
        h.engine.stop()
        await h.player.resume()
        #expect(h.engine.playCount == 2)
        // At least one real progress-timer tick while the replacement is still loading at zero.
        try await Task.sleep(for: .milliseconds(750))
        #expect(h.state.position == 37)
        await h.player.pause()
        #expect(h.state.position == 37)
        await h.player.stop()
    }

    @Test(arguments: [false, true])
    func failedRestoreNeverPlaysFromTheBeginning(downloaded: Bool) async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(3))
        if downloaded { await h.resolver.useDownloadedSource() }
        try await h.play()
        _ = await h.engine.seek(to: 37)
        h.state.position = 37
        h.engine.stop()
        await h.player.resume()
        try await h.waitUntil {
            h.report.components(separatedBy: "engine state=buffering").count >= 3
        }
        h.engine.failNextSeek()
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        #expect(h.engine.isReady)
        #expect(h.state.position == 37)
        if case .error = h.state.playbackState {} else {
            Issue.record("Failed restore must stop safely instead of unmuting the song at zero")
        }
        // A manual retry must still use the original checkpoint.
        await h.player.resume()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        #expect(h.engine.progress >= 37)
        #expect(h.engine.volume > 0)
        await h.player.stop()
    }

    private var mediaReset: AudioEngineFailure {
        .init(error: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.mediaServicesWereReset.rawValue))
    }

    private func confirmAudioResumed(_ h: RecoveryHarness) async throws {
        // A real player cannot become ready before its initial callbacks. Wait for both mock
        // startup events to reach the actor before sending the ready event through the test seam.
        try await h.waitUntil {
            let attempt = h.report.components(separatedBy: "audio-recovery attempt-started").last ?? ""
            return attempt.contains("engine state=paused") && attempt.contains("engine state=buffering")
        }
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        try await h.waitUntil { h.report.contains("audio-recovery progress-validated") }
    }

    @Test func mediaServicesFailureAutomaticallyRestoresAudioWithoutCheckingServerOrSkippingTracks() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        try await h.play(["a", "b", "c"])
        _ = await h.engine.seek(to: 37)
        h.state.position = 37
        let failedToken = h.engine.token
        h.engine.poisonMediaServices()
        await h.player.handleEngineError(mediaReset, playbackToken: failedToken)
        #expect(h.engine.resetCount == 1)
        #expect(h.audioSession.invalidations == 1)
        #expect(h.state.queue.map(\.id) == ["a", "b", "c"])
        #expect(h.state.currentTrack?.id == "a")
        #expect(h.state.wantsPlayback)
        #expect(h.state.position == 37)
        try await h.waitUntil { h.engine.playCount == 2 }
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        #expect(h.engine.progress == 37)
        #expect(h.engine.volume > 0)
        // The seek from zero and a transient playing event are not success.
        try await Task.sleep(for: .milliseconds(80))
        #expect(!h.report.contains("audio-recovery progress-validated"))
        try await confirmAudioResumed(h)
        #expect(await h.resolver.availabilityCalls == 0)
        #expect(!h.report.contains("item-rebuilt"))
        #expect(h.state.waitingReason == nil)

        // Callbacks from the discarded players cannot damage this or the following songs.
        await h.player.handleEngineError(mediaReset, playbackToken: failedToken)
        try await h.player.skipToNext()
        #expect(h.state.currentTrack?.id == "b")
        try await h.player.skipToNext()
        #expect(h.state.currentTrack?.id == "c")
        #expect(h.engine.playCount == 4)
        #expect(h.engine.resetCount == 1)
        await h.player.stop()
    }

    @Test func mediaServicesResetPreservesPausedPositionWithoutStartingAudio() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        try await h.play()
        _ = await h.engine.seek(to: 37)
        h.state.position = 37
        await h.player.pause()
        let activations = h.audioSession.activations
        let oldToken = h.engine.token
        await h.player.handleMediaServicesReset()
        try await Task.sleep(for: .milliseconds(120))
        #expect(h.engine.isReady)
        #expect(h.state.position == 37)
        #expect(h.state.playbackState == .paused)
        #expect(h.audioSession.activations == activations)
        await h.player.handleEngineState(.playing, playbackToken: oldToken)
        #expect(h.engine.playCount == 1)

        await h.player.resume()
        #expect(h.engine.playCount == 2)
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        #expect(h.engine.progress == 37)
        #expect(h.state.playbackState == .playing)
        await h.player.stop()
    }

    @Test func mediaServicesResetCancelsAnInFlightNetworkRecovery() async throws {
        let h = try RecoveryHarness()
        await h.resolver.configure(block: true)
        try await h.play()
        try await h.waitUntil { await h.resolver.availabilityCalls == 1 }
        await h.player.handleMediaServicesReset()
        await h.resolver.releaseAvailability(.available)
        try await h.waitUntil { h.engine.playCount == 2 }
        try await confirmAudioResumed(h)
        #expect(h.state.currentTrack?.id == "a")
        #expect(!h.report.contains("item-rebuilt"))
        #expect(await h.resolver.availabilityCalls == 1)
        await h.player.stop()
    }

    @Test func pauseCancelsRecoveryBeforeAnyAutomaticPlay() async throws {
        let h = try RecoveryHarness(audioRetryDelay: .milliseconds(200))
        try await h.play()
        await h.player.handleMediaServicesReset()
        await h.player.pause()
        try await Task.sleep(for: .milliseconds(300))
        #expect(h.engine.playCount == 1)
        #expect(h.state.playbackState == .paused)
        await h.player.stop()
    }

    @Test func nextSupersedesAudioRecoveryAndOldFailures() async throws {
        let h = try RecoveryHarness(audioRetryDelay: .milliseconds(200))
        try await h.play()
        let oldToken = h.engine.token
        await h.player.handleMediaServicesReset()
        try await h.player.skipToNext()
        await h.player.handleEngineError(mediaReset, playbackToken: oldToken)
        try await Task.sleep(for: .milliseconds(300))
        #expect(h.engine.playCount == 2)
        #expect(h.state.currentTrack?.id == "b")
        #expect(h.state.playbackState == .playing)
        #expect(h.engine.resetCount == 1)
        await h.player.stop()
    }

    @Test func globalResetDuringNextResolutionCannotRestartThePreviousTrack() async throws {
        let h = try RecoveryHarness(audioRetryDelay: .milliseconds(150))
        try await h.play()
        await h.player.handleMediaServicesReset()
        await h.resolver.blockResolution(of: "b")
        let next = Task { try await h.player.skipToNext() }
        try await h.waitUntil { await h.resolver.isResolvingBlockedTrack }
        await h.player.handleMediaServicesReset()
        try await Task.sleep(for: .milliseconds(200))
        #expect(h.engine.playCount == 1)
        await h.resolver.releaseResolution()
        try await next.value
        #expect(h.engine.playCount == 2)
        #expect(h.state.currentTrack?.id == "b")
        await h.player.stop()
    }

    @Test func recoveryWaitsForTheOriginalBluetoothOutput() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        h.audioSession.outputs = [RecoveryTestAudioSession.speaker]
        await h.player.handleMediaServicesReset()
        try await h.waitUntil { h.report.contains("waiting-for-route") }
        #expect(h.engine.playCount == 1)
        h.audioSession.outputs = [.init(uid: "different-headphones", portType: .bluetoothA2DP)]
        await h.player.handleRouteChange(.newDeviceAvailable)
        try await Task.sleep(for: .milliseconds(80))
        #expect(h.engine.playCount == 1)
        h.audioSession.outputs = [RecoveryTestAudioSession.headphones]
        await h.player.handleRouteChange(.newDeviceAvailable)
        try await h.waitUntil { h.engine.playCount == 2 }
        try await confirmAudioResumed(h)
        await h.player.stop()
    }

    @Test func recoveryUsesTheRouteAudioMovedToDuringPlayback() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        // The progress loop no longer polls the route; the change notification must record it.
        h.audioSession.outputs = [.init(uid: "different-headphones", portType: .bluetoothA2DP)]
        await h.player.handleRouteChange(.override)
        await h.player.handleMediaServicesReset()
        try await h.waitUntil { h.engine.playCount == 2 }
        try await confirmAudioResumed(h)
        await h.player.stop()
    }

    @Test func systemSuspensionBeforeResetStillRetainsPlayIntent() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        h.audioSession.outputs = [RecoveryTestAudioSession.speaker]
        await h.player.handleRouteChange(
            .oldDeviceUnavailable, previousRouteOutputs: [RecoveryTestAudioSession.headphones]
        )
        #expect(h.state.playbackState == .paused)
        await h.player.handleAudioSessionInterruption(.began(routeDisconnected: true))
        let activations = h.audioSession.activations
        await h.player.handleMediaServicesReset()
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.state.wantsPlayback)
        #expect(h.audioSession.activations == activations)
        #expect(h.engine.playCount == 1)
        h.audioSession.outputs = [RecoveryTestAudioSession.headphones]
        await h.player.handleAudioSessionInterruption(.ended(shouldResume: true))
        try await h.waitUntil { h.engine.playCount == 2 }
        try await confirmAudioResumed(h)
        await h.player.stop()
    }

    @Test func activationFailureRecoversAutomaticallyWithOneIncidentBudget() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        h.audioSession.failNextActivations(1)
        await h.player.handleMediaServicesReset()
        try await h.waitUntil { h.report.contains("activation-failed") }
        await h.player.handleMediaServicesReset() // duplicate OS signal must retain the budget
        try await h.waitUntil { h.engine.playCount == 2 }
        #expect(h.report.contains("audio-recovery attempt-started number=2"))
        try await confirmAudioResumed(h)
        #expect(await h.resolver.availabilityCalls == 0)
        await h.player.stop()
    }

    @Test func repeatedResetFailuresExhaustOneBudgetWithoutSkippingOrProbingTheServer() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        await h.player.handleMediaServicesReset()
        for count in 2...4 {
            try await h.waitUntil { h.engine.playCount == count }
            await h.player.handleEngineError(mediaReset, playbackToken: h.engine.token)
        }
        try await h.waitUntil { h.report.contains("audio-recovery exhausted") }
        #expect(h.engine.playCount == 4)
        #expect(h.state.currentTrack?.id == "a")
        #expect(await h.resolver.availabilityCalls == 0)
        #expect(!h.report.contains("retry-budget-exhausted"))
        guard case .error(.audioSystemUnavailable) = h.state.playbackState else {
            Issue.record("Persistent audio failure was not classified as an audio-system error")
            await h.player.stop()
            return
        }
        await h.player.stop()
    }

    @Test func stalledAudioRecoveryIsBoundedAndThirdAttemptCanSucceed() async throws {
        let h = try RecoveryHarness(audioStartupGrace: .milliseconds(600))
        try await h.play()
        await h.player.handleMediaServicesReset()
        try await h.waitUntil { h.engine.playCount == 4 }
        try await confirmAudioResumed(h)
        #expect(!h.report.contains("audio-recovery exhausted"))
        #expect(await h.resolver.availabilityCalls == 0)
        await h.player.stop()
    }

    @Test func interruptionWithoutResumePermissionLeavesRecoveredResourcesPaused() async throws {
        let h = try RecoveryHarness(audioRetryDelay: .milliseconds(150))
        try await h.play()
        await h.player.handleMediaServicesReset()
        await h.player.handleAudioSessionInterruption(.began(routeDisconnected: false))
        await h.player.handleAudioSessionInterruption(.ended(shouldResume: false))
        try await Task.sleep(for: .milliseconds(250))
        #expect(h.state.playbackState == .paused)
        #expect(h.engine.playCount == 1)
        #expect(h.report.contains("audio-recovery interrupted"))
        await h.player.stop()
    }

    @Test func networkChangeCannotRestartAnExhaustedAudioIncident() async throws {
        let h = try RecoveryHarness(audioStartupGrace: .milliseconds(100))
        try await h.play()
        await h.player.handleMediaServicesReset()
        try await h.waitUntil { h.report.contains("audio-recovery exhausted") }
        let plays = h.engine.playCount
        await h.player.handleNetworkPathChanged(NetworkPathEvent(
            generation: 1,
            descriptor: NetworkPathDescriptor(
                isOnline: true, isExpensive: true, isConstrained: false,
                supportsDNS: true, supportsIPv4: false, supportsIPv6: true,
                interfaces: [.cellular], gateways: []
            )
        ))
        try await Task.sleep(for: .milliseconds(200))
        #expect(h.engine.playCount == plays)
        #expect(await h.resolver.availabilityCalls == 0)
        guard case .error(.audioSystemUnavailable) = h.state.playbackState else {
            Issue.record("A network event replaced the audio-system failure")
            await h.player.stop()
            return
        }
        await h.player.stop()
    }

    @Test func routeLossDuringValidationNeverCompletesOnSpeaker() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        await h.player.handleMediaServicesReset()
        try await h.waitUntil { h.engine.playCount == 2 }
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        // Route notifications may be delayed: the validator must inspect the live route itself.
        h.audioSession.outputs = [RecoveryTestAudioSession.speaker]
        try await Task.sleep(for: .milliseconds(350))
        #expect(!h.report.contains("audio-recovery progress-validated"))
        #expect(h.engine.isReady)
        h.audioSession.outputs = [RecoveryTestAudioSession.headphones]
        try await h.waitUntil { h.engine.playCount == 3 }
        try await confirmAudioResumed(h)
        await h.player.stop()
    }

    @Test func seekDuringRecoveryReplacesTheCheckpoint() async throws {
        let h = try RecoveryHarness(audioRetryDelay: .milliseconds(150))
        try await h.play()
        h.state.position = 37
        await h.player.handleMediaServicesReset()
        await h.player.seek(to: 62)
        try await h.waitUntil { h.engine.playCount == 2 }
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        #expect(h.engine.progress == 62)
        try await confirmAudioResumed(h)
        await h.player.stop()
    }

    @Test func queueUndoSurvivesNextWithoutRestartingPlayback() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        try await h.play(["a", "b", "c", "d"])
        let selection = try #require(QueueTrackSelection(playerState: h.state, destinationIndex: 1, destinationTrackID: "b"))
        let removal = try #require(await h.player.removeQueueTrack(selection))
        try await h.player.skipToNext()
        #expect(h.state.currentTrack?.id == "c")
        let plays = h.engine.playCount
        #expect(await h.player.restoreQueueTrack(removal))
        #expect(h.state.queue.map(\.id) == ["a", "b", "c", "d"])
        #expect(h.state.currentIndex == 2)
        #expect(h.state.currentTrack?.id == "c")
        #expect(h.engine.playCount == plays)
        await h.player.stop()
    }

    @Test func ordinaryNextDoesNotPresentAReconnection() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(2))
        try await h.play()
        for _ in 0..<3 {
            await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        }
        #expect(h.state.waitingReason != .reconnecting)
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        try await h.player.skipToNext()
        #expect(h.state.currentTrack?.id == "b")
        for _ in 0..<3 {
            await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        }
        #expect(h.state.waitingReason != .reconnecting)
        #expect(!h.report.contains("attempt-started"))
        await h.player.stop()
    }
    @Test func slowStartupAndRepeatedBufferingDoNotRebuildEarly() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(2))
        try await h.play()
        for _ in 0..<8 {
            await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(h.engine.playCount == 1)
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        try await h.waitUntil { h.report.contains("progress-validated") }
        #expect(h.engine.playCount == 1)
        #expect(h.state.playbackState == .playing)
        await h.player.stop()
    }

    @Test func thirdRebuildCanActuallyStartAndValidate() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        try await h.waitUntil { h.engine.playCount == 4 }
        let stops = h.engine.stopCount
        for _ in 0..<6 {
            await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        }
        #expect(h.engine.stopCount == stops)
        #expect(h.state.playbackState == .playing)
        #expect(h.state.waitingReason == .reconnecting)
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        try await h.waitUntil { h.report.contains("progress-validated") }
        #expect(!h.report.contains("retry-budget-exhausted"))
        #expect(h.engine.playCount == 4)
        await h.player.stop()
    }

    @Test func stalledLastAttemptStopsOnceAndManualNextStillWorks() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        try await h.waitUntil { if case .error = h.state.playbackState { true } else { false } }
        #expect(h.engine.playCount == 4)
        #expect(h.report.components(separatedBy: "retry-budget-exhausted").count == 2)
        let oldToken = h.engine.token
        try await h.player.skipToNext()
        await h.player.handleEngineError(.init(error: URLError(.timedOut)), playbackToken: oldToken)
        #expect(h.state.currentTrack?.id == "b")
        #expect(h.state.playbackState == .playing)
        #expect(h.engine.playCount == 5)
        await h.player.stop()
    }

    @Test func explicitPlayAfterExhaustionGetsAFreshBudget() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        try await h.waitUntil { if case .error = h.state.playbackState { true } else { false } }
        await h.player.resume()
        #expect(h.engine.playCount == 5)
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        try await h.waitUntil { h.report.contains("progress-validated") }
        #expect(h.state.playbackState == .playing)
        await h.player.stop()
    }

    @Test func confirmedMissingSongAdvancesWithoutChangingTheQueue() async throws {
        let h = try RecoveryHarness()
        await h.resolver.configure(missing: ["a"])
        try await h.play()
        await h.player.handleEngineError(.init(error: URLError(.badServerResponse)), playbackToken: h.engine.token)
        try await h.waitUntil { h.state.currentTrack?.id == "b" }
        #expect(h.state.queue.map(\.id) == ["a", "b"])
        #expect(h.engine.playCount == 2)
        #expect(h.report.contains("media-availability=missing"))
        await h.player.stop()
    }

    @Test func anEntireMissingQueueStopsEvenWithRepeatAllAndDuplicates() async throws {
        let h = try RecoveryHarness()
        await h.resolver.configure(missing: ["a", "b"])
        try await h.play(["a", "a", "b"])
        h.state.repeatMode = .all
        try await h.waitUntil { h.report.contains("unavailable-track has-next=false") }
        #expect(h.engine.playCount == 2)
        #expect(h.state.queue.count == 3)
        if case .error(.mediaNotFound) = h.state.playbackState {} else { Issue.record("Expected missing-media error") }
        await h.player.stop()
    }

    @Test func pauseWinsOverASuspendedMissingSongLookup() async throws {
        let h = try RecoveryHarness()
        await h.resolver.configure(block: true)
        try await h.play()
        try await h.waitUntil { await h.resolver.availabilityCalls == 1 }
        await h.player.pause()
        await h.resolver.releaseAvailability(.missing)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.state.currentTrack?.id == "a")
        #expect(h.state.playbackState == .paused)
        #expect(h.engine.playCount == 1)
        await h.player.stop()
    }

    @Test func nextWinsOverASuspendedMissingSongLookup() async throws {
        let h = try RecoveryHarness()
        await h.resolver.configure(block: true)
        try await h.play()
        try await h.waitUntil { await h.resolver.availabilityCalls == 1 }
        try await h.player.skipToNext()
        await h.resolver.releaseAvailability(.missing)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.state.currentTrack?.id == "b")
        #expect(h.state.playbackState == .playing)
        #expect(h.engine.playCount == 2)
        await h.player.stop()
    }
    @Test func pauseWinsOverPlaylistPreparation() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(3))
        try await h.play()
        let tracks = h.state.queue
        let gate = PlaylistPreparationGate()
        let request = Task {
            try await h.player.play(preparingQueue: {
                await gate.wait()
                return PreparedPlaybackQueue(tracks: tracks, startIndex: 1, repeatMode: .all)
            })
        }
        try await h.waitUntil { await gate.isWaiting }
        await h.player.pause()
        await gate.release()
        try await request.value
        #expect(h.state.currentTrack?.id == "a")
        #expect(h.state.playbackState == .paused)
        #expect(h.engine.playCount == 1)
        #expect(h.state.repeatMode == .off)
        await h.player.stop()
    }

    @Test func preparedPlaybackAppliesExplicitRepeatMode() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(3))
        try await h.play()
        let tracks = h.state.queue
        try await h.player.play(preparingQueue: {
            PreparedPlaybackQueue(tracks: tracks, startIndex: 0, repeatMode: .all)
        })
        #expect(h.state.repeatMode == .all)
        await h.player.stop()
    }
}

private actor PlaylistPreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}


@Suite("Gapless standby preload", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct GaplessStandbyPreloadTests {
    /// Starts a three-track queue with 10 s left of the first track, inside the 15 s preload window.
    private func playNearTheEnd(_ h: RecoveryHarness) async throws {
        try await h.play(["a", "b", "c"])
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        _ = await h.engine.seek(to: 110)
    }

    @Test func failedResolveIsRetriedAndLeavesAStandbyDeckReady() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        await h.resolver.failResolutions(of: "b", count: 1)
        try await playNearTheEnd(h)
        try await h.waitUntil { !h.engine.preloads.isEmpty }
        #expect(await h.resolver.resolveCalls["b"] == 2)
        #expect(h.engine.preloads.map { $0.trackID } == ["b"])
        #expect(h.engine.preloads.first?.expectedCurrentTrackID == "a")
        // The natural hand-off adopts the prepared source rather than resolving the song again.
        await h.player.handleEndOfTrack(AudioEngineTrackEnd(
            endedPlaybackToken: h.engine.token, endedPosition: 120, promotedPlayback: nil
        ))
        #expect(h.state.currentTrack?.id == "b")
        #expect(h.engine.playCount == 2)
        #expect(await h.resolver.resolveCalls["b"] == 2, "\(h.report)")
        await h.player.stop()
    }

    @Test func cancelWhileARetryIsPendingStartsAFreshPreloadForTheNewNextTrack() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10), prefetchRetryDelay: .milliseconds(500))
        await h.resolver.failResolutions(of: "b", count: 1)
        try await playNearTheEnd(h)
        try await h.waitUntil { await h.resolver.resolveCalls["b"] == 1 }
        // The retry for "b" is now waiting out its backoff. Removing "b" changes the next track.
        let selection = try #require(QueueTrackSelection(playerState: h.state, destinationIndex: 1, destinationTrackID: "b"))
        _ = try #require(await h.player.removeQueueTrack(selection))
        try await h.waitUntil { !h.engine.preloads.isEmpty }
        try await Task.sleep(for: .milliseconds(700))
        #expect(await h.resolver.resolveCalls["b"] == 1, "\(h.report)")
        #expect(h.engine.preloads.map { $0.trackID } == ["c"])
        #expect(h.engine.preloads.first?.expectedCurrentTrackID == "a")
        await h.player.stop()
    }

    @Test func exhaustedRetryBudgetStopsResolvingUntilTheContextChanges() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        await h.resolver.failResolutions(of: "b", count: 10)
        try await playNearTheEnd(h)
        try await h.waitUntil { await h.resolver.resolveCalls["b"] == PlayerService.maximumPrefetchAttempts }
        // Several more progress ticks: none of them may start another round of attempts.
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(await h.resolver.resolveCalls["b"] == PlayerService.maximumPrefetchAttempts, "\(h.report)")
        #expect(h.engine.preloads.isEmpty)
        await h.player.stop()
    }

    @Test func standbyThatFailsToLoadIsPreloadedAgain() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        try await playNearTheEnd(h)
        try await h.waitUntil { h.engine.preloads.count == 1 }
        h.engine.failStandby(trackID: "b")
        try await h.waitUntil { h.engine.preloads.count == 2 }
        #expect(h.engine.preloads.map { $0.trackID } == ["b", "b"])
        #expect(await h.resolver.resolveCalls["b"] == 2)
        // The hand-off adopts the source of the second, working standby deck.
        await h.player.handleEndOfTrack(AudioEngineTrackEnd(
            endedPlaybackToken: h.engine.token, endedPosition: 120, promotedPlayback: nil
        ))
        #expect(h.state.currentTrack?.id == "b")
        #expect(await h.resolver.resolveCalls["b"] == 2, "\(h.report)")
        await h.player.stop()
    }

    @Test func standbyLoadFailuresShareTheRetryBudget() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        try await playNearTheEnd(h)
        for attempt in 1...PlayerService.maximumPrefetchAttempts {
            try await h.waitUntil { h.engine.preloads.count == attempt }
            h.engine.failStandby(trackID: "b")
        }
        // Several more progress ticks: the exhausted track must not be preloaded again.
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(h.engine.preloads.count == PlayerService.maximumPrefetchAttempts, "\(h.report)")
        // A failure report for a deck that is no longer prepared is ignored.
        h.engine.failStandby(trackID: "b")
        try await Task.sleep(for: .milliseconds(300))
        #expect(h.engine.preloads.count == PlayerService.maximumPrefetchAttempts)
        await h.player.stop()
    }

    @Test func retryBackoffGrowsWithEachAttempt() {
        #expect(PlayerService.prefetchRetryDelay(base: .seconds(1), retry: 1) == .seconds(1))
        #expect(PlayerService.prefetchRetryDelay(base: .seconds(1), retry: 2) == .seconds(2))
        // Two retries after a 15 s preload window opens still leave the transition 12 s.
        let total = (1..<PlayerService.maximumPrefetchAttempts)
            .map { PlayerService.prefetchRetryDelay(base: .seconds(1), retry: $0) }
            .reduce(Duration.zero, +)
        #expect(total <= .seconds(3))
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor
struct LocalMusicPlaybackTests {
    @Test func localQueuePlaysAndAdvancesWithoutAServer() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LocalMusicFixture.wav(at: folder.appendingPathComponent("First.wav"))
        try LocalMusicFixture.wav(at: folder.appendingPathComponent("Second.wav"))
        let store = LocalMusicStore(directory: root.appendingPathComponent("Index"))
        try await store.add([folder])
        let songs = try await store.refresh().tracks.map(\.song)
        let harness = try RecoveryHarness(localMusicStore: store, configureServer: false)
        try await harness.player.play(tracks: songs, startIndex: 0)
        #expect(harness.engine.sourceURL?.lastPathComponent == "First.wav")
        #expect(harness.state.currentTrack?.isLocalFile == true)
        try await harness.player.skipToNext()
        #expect(harness.engine.sourceURL?.lastPathComponent == "Second.wav")
        await harness.player.pause()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Second.wav"))
        await harness.player.resume()
        #expect(harness.state.playbackState == .paused)
        await harness.player.stop()
    }
}

// MARK: - Full download of the playing song

/// Serves audio for every request, after an optional run of connection failures.
private nonisolated final class AudioDownloadStubProtocol: URLProtocol, @unchecked Sendable {
    private struct State: Sendable {
        var failuresRemaining = 0
        var requests: [URLRequest] = []
        var responseDelay: Duration = .zero
    }
    private static let state = Mutex(State())
    static let audio = Data("ID3 streamed audio fixture".utf8)

    static func reset(failures: Int = 0, responseDelay: Duration = .zero) {
        state.withLock { $0 = State(failuresRemaining: failures, responseDelay: responseDelay) }
    }
    static var requests: [URLRequest] { state.withLock { $0.requests } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioDownloadStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let (fails, delay) = Self.state.withLock { state -> (Bool, Duration) in
            state.requests.append(request)
            guard state.failuresRemaining > 0 else { return (false, state.responseDelay) }
            state.failuresRemaining -= 1
            return (true, .zero)
        }
        if fails {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let respond: @Sendable () -> Void = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "\(Self.audio.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.audio)
            client?.urlProtocolDidFinishLoading(self)
        }
        if delay > .zero {
            let milliseconds = Int(delay.components.seconds * 1_000 + delay.components.attoseconds / 1_000_000_000_000_000)
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: respond)
        } else {
            respond()
        }
    }
}

@MainActor
private final class RecordingAudioStreamCache: AudioStreamCacheProtocol {
    private(set) var stored: [(songId: String, quality: CachedAudioQuality)] = []
    /// Runs after a copy is stored, before the player hears about it.
    var onStore: (@MainActor () async -> Void)?
    var usedBytes: Int64 { 0 }
    var trackCount: Int { stored.count }
    var maxBytes: Int64 { AudioStreamCache.defaultMaxBytes }
    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func store(fileAt sourceURL: URL, forSongId songId: String, serverId: UUID, mimeType: String) async throws -> URL {
        try await store(fileAt: sourceURL, forSongId: songId, serverId: serverId, mimeType: mimeType, quality: .unrecorded)
    }
    func store(fileAt sourceURL: URL, forSongId songId: String, serverId: UUID, mimeType: String,
               quality: CachedAudioQuality) async throws -> URL {
        stored.append((songId, quality))
        await onStore?()
        return sourceURL
    }
    func setMaxBytes(_ value: Int64) async {}
    func invalidate(songId: String, serverId: UUID) async {}
    func clearAll() async {}
    func clearAllForServer(_ serverId: UUID) async {}
}

@Suite("Full download of the playing song", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct CurrentSongDownloadTests {
    private func path(expensive: Bool, constrained: Bool) -> NetworkPathEvent {
        NetworkPathEvent(generation: 0, descriptor: NetworkPathDescriptor(
            isOnline: true, isExpensive: expensive, isConstrained: constrained,
            supportsDNS: true, supportsIPv4: true, supportsIPv6: true,
            interfaces: [.cellular], gateways: []
        ))
    }

    private func harness(cache: RecordingAudioStreamCache, expensive: Bool = true, constrained: Bool = false) throws -> RecoveryHarness {
        let h = try RecoveryHarness(startupGrace: .seconds(10), audioStreamCache: cache,
                                    cacheSession: AudioDownloadStubProtocol.session(), streamCacheFormat: .matchStream)
        h.server.state.networkPathEvent = path(expensive: expensive, constrained: constrained)
        return h
    }

    @Test func aStreamedSongDownloadsInFullFromItsFirstSecondOnCellular() async throws {
        AudioDownloadStubProtocol.reset()
        let cache = RecordingAudioStreamCache()
        let h = try harness(cache: cache)
        try await h.play()
        // Well inside the 30 s delay the download used to wait for.
        try await h.waitUntil { cache.trackCount == 1 }
        #expect(cache.stored.first?.songId == "a")
        #expect(cache.stored.first?.quality == .original)
        let request = try #require(AudioDownloadStubProtocol.requests.first)
        #expect(request.allowsCellularAccess)
        #expect(!request.allowsConstrainedNetworkAccess)
        try await h.waitUntil { !h.state.currentSongNeedsNetwork }
        await h.player.stop()
    }

    @Test func lowDataModeKeepsToTheStreamAlone() async throws {
        AudioDownloadStubProtocol.reset()
        let cache = RecordingAudioStreamCache()
        let h = try harness(cache: cache, constrained: true)
        try await h.play()
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        // Several progress ticks: the skip must not be retried on each one.
        try await Task.sleep(for: .milliseconds(1_300))
        #expect(h.report.components(separatedBy: "skipped-power-or-data").count == 2)
        #expect(AudioDownloadStubProtocol.requests.isEmpty)
        #expect(cache.trackCount == 0)
        #expect(!h.state.currentSongNeedsNetwork)
        await h.player.stop()
    }

    @Test func lowPowerModeDoesNotStopTheDownload() {
        #expect(PlayerService.allowsFullDownload(pathIsConstrained: false, lowPowerMode: true))
        #expect(!PlayerService.allowsFullDownload(pathIsConstrained: true, lowPowerMode: false))
    }

    @Test func aDroppedConnectionIsRetriedWithBackoff() async throws {
        AudioDownloadStubProtocol.reset(failures: 2)
        let cache = RecordingAudioStreamCache()
        let h = try harness(cache: cache)
        try await h.play()
        try await h.waitUntil { cache.trackCount == 1 }
        #expect(AudioDownloadStubProtocol.requests.count == 3)
        await h.player.stop()
    }
}

// MARK: - Now Playing while buffering

@MainActor
private final class RecordingNowPlaying: NowPlayingServiceProtocol {
    struct Push: Equatable {
        let elapsed: TimeInterval
        let rate: Float
    }
    private(set) var pushes: [Push] = []
    private(set) var updateRates: [Float] = []
    func start() async {}
    func stop() async {}
    func setFavoritesService(_ service: any FavoritesServiceProtocol) async {}
    func update(with snapshot: NowPlayingSnapshot) async { updateRates.append(snapshot.playbackRate) }
    func pushPosition(elapsed: TimeInterval, rate: Float, duration: TimeInterval, songId: String) async {
        pushes.append(Push(elapsed: elapsed, rate: rate))
    }
}

@Suite("Now Playing while buffering", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct NowPlayingBufferingTests {
    @Test func theClockStopsWhileBufferingAndRestartsWithTheAudio() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10), stallGrace: .seconds(20))
        let nowPlaying = RecordingNowPlaying()
        await h.player.setNowPlayingService(nowPlaying)
        try await h.play()
        try await h.waitUntil { h.report.contains("engine state=buffering") }
        // Opening the stream already counts as waiting.
        try await h.waitUntil { nowPlaying.updateRates.last == 0 }
        _ = await h.engine.seek(to: 37)
        h.state.position = 37
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        #expect(nowPlaying.pushes.last?.rate == 1)
        #expect(abs((nowPlaying.pushes.last?.elapsed ?? 0) - 37) < 1)

        // A mid-song stall: the media clock freezes and Now Playing must say so.
        try await Task.sleep(for: .milliseconds(300))
        h.engine.pause()
        let frozen = h.engine.progress
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        let stalled = try #require(nowPlaying.pushes.last)
        #expect(stalled.rate == 0)
        #expect(abs(stalled.elapsed - frozen) < 0.01)
        let pushesWhileStalled = nowPlaying.pushes.count
        // Progress ticks during the stall must not restart the clock.
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(!nowPlaying.pushes.dropFirst(pushesWhileStalled).contains { $0.rate > 0 })

        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        let resumed = try #require(nowPlaying.pushes.last)
        #expect(resumed.rate == 1)
        #expect(abs(resumed.elapsed - frozen) < 0.2)
        await h.player.stop()
    }

    @Test func aDeliberatePauseIsNotReportedAsBuffering() async throws {
        let h = try RecoveryHarness(startupGrace: .seconds(10))
        let nowPlaying = RecordingNowPlaying()
        await h.player.setNowPlayingService(nowPlaying)
        try await h.play()
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        await h.player.pause()
        let pushes = nowPlaying.pushes.count
        await h.player.handleEngineState(.paused, playbackToken: h.engine.token)
        #expect(nowPlaying.pushes.count == pushes)
        await h.player.stop()
    }
}

// MARK: - Patient stall recovery

@Suite("Stall recovery while data arrives", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct PatientStallRecoveryTests {
    /// Starts song "a" and lets it play into the middle of the track.
    private func playing(_ h: RecoveryHarness) async throws {
        try await h.play()
        try await h.waitUntil { h.report.contains("engine state=buffering") }
        _ = await h.engine.seek(to: 60)
        h.state.position = 60
        h.engine.startAdvancing()
        await h.player.handleEngineState(.playing, playbackToken: h.engine.token)
        // The startup watch confirms the item by its moving playhead before the stall begins.
        try await h.waitUntil { h.report.contains("progress-validated") }
    }

    @Test func aStallIsNotRebuiltWhileDataKeepsArrivingAndSkipsTheServerCheck() async throws {
        let h = try RecoveryHarness(startupGrace: .milliseconds(800), stallGrace: .milliseconds(100),
                                    dataFlowingGrace: .milliseconds(900))
        try await playing(h)
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        // Data trickles in long past the 100 ms stall grace: the buffered item must be kept.
        for _ in 0..<15 {
            h.engine.receiveData(seconds: 1)
            try await Task.sleep(for: .milliseconds(40))
        }
        #expect(h.engine.playCount == 1)
        #expect(!h.report.contains("item-rebuilt"))
        // Data stops arriving; the next check rebuilds the item without asking the server.
        try await h.waitUntil { h.engine.playCount == 2 }
        #expect(await h.resolver.availabilityCalls == 0)
        #expect(h.state.position >= 60)
        await h.player.stop()
    }

    @Test func aStallWithNothingArrivingIsRebuiltAfterTheShortGrace() async throws {
        let h = try RecoveryHarness(startupGrace: .milliseconds(800), stallGrace: .milliseconds(100),
                                    dataFlowingGrace: .seconds(10))
        try await playing(h)
        let stalled = ContinuousClock.now
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        try await h.waitUntil { h.engine.playCount == 2 }
        #expect(stalled.duration(to: .now) < .seconds(2))
        #expect(await h.resolver.availabilityCalls == 0)
        await h.player.stop()
    }

    @Test func aStallWithACompleteCopySwitchesAtOnce() async throws {
        let h = try RecoveryHarness(startupGrace: .milliseconds(800), stallGrace: .seconds(20))
        try await playing(h)
        // The first stall arms the long stream grace; the copy then completes.
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        await h.resolver.useCachedSource()
        let stalled = ContinuousClock.now
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        try await h.waitUntil { h.engine.playCount == 2 }
        #expect(stalled.duration(to: .now) < .seconds(2))
        #expect(h.engine.sourceURL?.lastPathComponent == "recovery-test-cache.m4a")
        #expect(await h.resolver.availabilityCalls == 0)
        #expect(h.state.position >= 60)
        await h.player.stop()
    }

    @Test func aLowerQualityCopyWaitsLikeTheStreamBeforeTakingOver() async throws {
        let h = try RecoveryHarness(startupGrace: .milliseconds(800), stallGrace: .milliseconds(600))
        try await playing(h)
        await h.resolver.useLowerQualityCachedSource()
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        try await Task.sleep(for: .milliseconds(250))
        #expect(h.engine.playCount == 1, "A brief stall must not drop a Wi-Fi original to a cellular transcode")
        try await h.waitUntil { h.engine.playCount == 2 }
        #expect(h.engine.sourceURL?.lastPathComponent == "recovery-test-cache.m4a")
        #expect(await h.resolver.availabilityCalls == 0)
        await h.player.stop()
    }

    @Test func aDownloadFinishingDuringAStallTakesOverAtOnce() async throws {
        AudioDownloadStubProtocol.reset(responseDelay: .milliseconds(900))
        let cache = RecordingAudioStreamCache()
        let h = try RecoveryHarness(startupGrace: .milliseconds(800), audioStreamCache: cache,
                                    cacheSession: AudioDownloadStubProtocol.session(),
                                    streamCacheFormat: .matchStream, stallGrace: .seconds(20))
        cache.onStore = { await h.resolver.useCachedSource() }
        try await playing(h)
        await h.player.handleEngineState(.buffering, playbackToken: h.engine.token)
        #expect(h.engine.playCount == 1)
        try await h.waitUntil { cache.trackCount == 1 }
        try await h.waitUntil { h.engine.playCount == 2 }
        #expect(h.engine.sourceURL?.lastPathComponent == "recovery-test-cache.m4a")
        #expect(await h.resolver.availabilityCalls == 0)
        await h.player.stop()
    }

    @Test func anItemFailureStillAsksTheServerWhetherTheSongExists() async throws {
        let h = try RecoveryHarness(startupGrace: .milliseconds(800))
        await h.resolver.configure(missing: ["a"])
        try await playing(h)
        await h.player.handleEngineError(.init(error: URLError(.badServerResponse)), playbackToken: h.engine.token)
        try await h.waitUntil { h.state.currentTrack?.id == "b" }
        #expect(await h.resolver.availabilityCalls == 1)
        await h.player.stop()
    }
}

@Suite("Now Playing ownership", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct NowPlayingOwnershipTests {
    /// Releasing the session on pause handed Now Playing back to Music, so a car or headphones
    /// connecting later started Music instead of resuming here.
    @Test func pausingKeepsTheAudioSessionAndStoppingReleasesIt() async throws {
        let h = try RecoveryHarness()
        try await h.play()
        await h.player.pause()
        #expect(h.audioSession.deactivations == 0)
        await h.player.stop()
        #expect(h.audioSession.deactivations == 1)
    }
}

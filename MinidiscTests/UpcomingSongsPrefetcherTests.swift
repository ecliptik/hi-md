import Foundation
import SwiftData
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

/// Serves a fixed audio body for every song, after an optional run of dropped connections.
private nonisolated final class PrefetchStubProtocol: URLProtocol, @unchecked Sendable {
    private struct State: Sendable {
        var failuresRemaining = 0
        var songIDs: [String] = []
    }
    private static let state = Mutex(State())
    static let audio = Data("ID3 upcoming song fixture".utf8)

    static func reset(failures: Int = 0) { state.withLock { $0 = State(failuresRemaining: failures) } }
    /// One entry per request, including failed attempts.
    static var requestedSongIDs: [String] { state.withLock { $0.songIDs } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrefetchStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value ?? "?"
        let fails = Self.state.withLock { state -> Bool in
            state.songIDs.append(id)
            guard state.failuresRemaining > 0 else { return false }
            state.failuresRemaining -= 1
            return true
        }
        if fails {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "\(Self.audio.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.audio)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Upcoming songs pre-caching", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct UpcomingSongsPrefetcherTests {
    private struct Harness {
        let prefetcher: UpcomingSongsPrefetcher
        let player = PlayerState()
        let server = MockServerService()
        let cache: AudioStreamCache
        let settings: CacheSettings
        let serverID: UUID

        init(maxBytes: Int64 = AudioStreamCache.defaultMaxBytes, cellular: Bool = true, constrained: Bool = false) throws {
            let models = try ModelContainer.minidisc(inMemory: true)
            let snapshot = ServerSnapshot(from: ServerConfig(displayName: "Fixture", baseURL: "https://example.invalid", username: "alice"))
            serverID = snapshot.id
            server.state.activeServer = snapshot
            server.state.activeConnectionVersion = .init(serverID: snapshot.id, revision: 1)
            server.state.hasObservedNetworkPath = true
            server.state.networkPathEvent = NetworkPathEvent(generation: 1, descriptor: NetworkPathDescriptor(
                isOnline: true, isExpensive: cellular, isConstrained: constrained,
                supportsDNS: true, supportsIPv4: true, supportsIPv6: true,
                interfaces: cellular ? [.cellular] : [.wifi], gateways: []
            ))
            server.connection = try ServerConnection(version: server.state.activeConnectionVersion!, server: snapshot,
                                                     credentials: ServerCredentials(password: "fixture", customHeaders: [:]))
            cache = AudioStreamCache(modelContainer: models, maxBytes: maxBytes)
            settings = CacheSettings(defaults: UserDefaults(suiteName: "UpcomingSongsPrefetcher.\(UUID())")!)
            let streamSettings = StreamSettings(defaults: UserDefaults(suiteName: "UpcomingSongsPrefetcherStream.\(UUID())")!)
            let resolver = MediaResolver(
                downloadService: DownloadService(serverService: server, modelContainer: models, toastService: ToastService()),
                audioStreamCache: cache, serverService: server, serverState: server.state, streamSettings: streamSettings
            )
            prefetcher = UpcomingSongsPrefetcher(
                playerState: player, server: server, resolver: resolver, cache: cache, settings: settings,
                streamSettings: streamSettings, session: PrefetchStubProtocol.session(),
                settleDelay: .milliseconds(20), retryDelay: .milliseconds(20)
            )
            let queue = (0..<8).map { DisplayableSong(from: Song(id: "s\($0)", title: "\($0)")) }
            player.queue = queue
            player.currentIndex = 0
            player.currentTrack = queue[0]
        }

        func cachedIDs() async -> [String] {
            var ids: [String] = []
            for index in 0..<8 where await cache.cachedURL(forSongId: "s\(index)", serverId: serverID) != nil {
                ids.append("s\(index)")
            }
            return ids
        }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(await condition())
    }

    @Test func cellularCachesTheNextThreeOnceThePlayingSongIsDownloaded() async throws {
        PrefetchStubProtocol.reset()
        let h = try Harness()
        h.player.currentSongNeedsNetwork = true
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(PrefetchStubProtocol.requestedSongIDs.isEmpty, "Pre-caching must wait for the playing song's download")

        h.player.currentSongNeedsNetwork = false
        try await waitUntil { await h.cachedIDs() == ["s1", "s2", "s3"] }
        try await Task.sleep(for: .milliseconds(150))
        #expect(PrefetchStubProtocol.requestedSongIDs == ["s1", "s2", "s3"])
        #expect(await h.cache.cachedEntry(forSongId: "s1", serverId: h.serverID)?.quality == .original)
        await h.cache.clearAll()
    }

    @Test func theCellularLimitIsASetting() async throws {
        PrefetchStubProtocol.reset()
        let h = try Harness()
        h.settings.cellularLookahead = .songs(1)
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await waitUntil { await h.cachedIDs() == ["s1"] }
        h.settings.cellularLookahead = .songs(0)
        h.player.currentIndex = 1
        h.player.currentTrack = h.player.queue[1]
        try await Task.sleep(for: .milliseconds(200))
        #expect(PrefetchStubProtocol.requestedSongIDs == ["s1"])
        await h.cache.clearAll()
    }

    @Test func failedDownloadsAreRetriedInsteadOfAbandoningTheQueue() async throws {
        PrefetchStubProtocol.reset(failures: 3)
        let h = try Harness()
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await waitUntil { await h.cachedIDs() == ["s1", "s2", "s3"] }
        #expect(PrefetchStubProtocol.requestedSongIDs.prefix(4) == ["s1", "s1", "s1", "s1"])
        await h.cache.clearAll()
    }

    @Test func nothingIsFetchedNearATransition() async throws {
        PrefetchStubProtocol.reset()
        let h = try Harness()
        h.player.isNearTrackTransition = true
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(PrefetchStubProtocol.requestedSongIDs.isEmpty)
        h.player.isNearTrackTransition = false
        try await waitUntil { await h.cachedIDs().count == 3 }
        await h.cache.clearAll()
    }

    @Test func lowDataModeTurnsPreCachingOff() async throws {
        PrefetchStubProtocol.reset()
        let h = try Harness(constrained: true)
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(PrefetchStubProtocol.requestedSongIDs.isEmpty)
    }

    @Test func wiFiWorksDownTheQueueUntilTheCacheSizeLimit() async throws {
        PrefetchStubProtocol.reset()
        // Room for two songs and a little more: the estimate of a third would not fit.
        let size = Int64(PrefetchStubProtocol.audio.count)
        let h = try Harness(maxBytes: size * 2 + 1, cellular: false)
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await waitUntil { await h.cachedIDs() == ["s1", "s2"] }
        try await Task.sleep(for: .milliseconds(200))
        #expect(PrefetchStubProtocol.requestedSongIDs == ["s1", "s2"])
        await h.cache.clearAll()
    }

    @Test func wiFiCachesTheEntireQueueByDefault() async throws {
        PrefetchStubProtocol.reset()
        let h = try Harness(cellular: false)
        #expect(h.settings.wifiLookahead == .entireQueue)
        #expect(h.settings.cellularLookahead == .songs(3))
        h.prefetcher.start()
        defer { h.prefetcher.stop() }
        try await waitUntil { await h.cachedIDs() == ["s1", "s2", "s3", "s4", "s5", "s6", "s7"] }
        await h.cache.clearAll()
    }

    @Test func policyRespectsLowDataModeButNotLowPowerMode() {
        func path(cellular: Bool, constrained: Bool) -> NetworkPathDescriptor {
            NetworkPathDescriptor(isOnline: true, isExpensive: cellular, isConstrained: constrained,
                                  supportsDNS: true, supportsIPv4: true, supportsIPv6: true,
                                  interfaces: cellular ? [.cellular] : [.wifi], gateways: [])
        }
        func lookahead(_ path: NetworkPathDescriptor, lowPower: Bool = false, needsNetwork: Bool = false,
                       nearTransition: Bool = false, cellular: CacheLookahead = .songs(3)) -> CacheLookahead? {
            UpcomingSongsPrefetcher.lookahead(
                enabled: true, isOnline: true, hasObservedPath: true, path: path,
                wifi: .entireQueue, cellular: cellular, currentSongNeedsNetwork: needsNetwork,
                isNearTrackTransition: nearTransition, lowPowerMode: lowPower
            )
        }
        #expect(lookahead(path(cellular: true, constrained: false)) == .songs(3))
        #expect(lookahead(path(cellular: true, constrained: false), lowPower: true) == .songs(3))
        #expect(lookahead(path(cellular: false, constrained: false), lowPower: true) == .entireQueue)
        #expect(lookahead(path(cellular: false, constrained: true)) == nil)
        #expect(lookahead(path(cellular: true, constrained: false), needsNetwork: true) == nil)
        #expect(lookahead(path(cellular: true, constrained: false), nearTransition: true) == nil)
        #expect(lookahead(path(cellular: true, constrained: false), cellular: .songs(0)) == nil)
    }

    @Test func entireQueueCandidatesSkipLocalFiles() {
        let queue = (0..<6).map { DisplayableSong(from: Song(id: "s\($0)", title: "\($0)")) }
        #expect(UpcomingSongsPrefetcher.candidates(queue: queue, currentIndex: 1, lookahead: nil).map(\.id) == ["s2", "s3", "s4", "s5"])
    }

    @Test func lookaheadSettingsSurviveRelaunch() throws {
        let name = "UpcomingSongsPrefetcherSettings.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = CacheSettings(defaults: defaults)
        settings.wifiLookahead = .songs(10)
        settings.cellularLookahead = .songs(0)
        let restored = CacheSettings(defaults: defaults)
        #expect(restored.wifiLookahead == .songs(10))
        #expect(restored.cellularLookahead == .songs(0))
        restored.wifiLookahead = .entireQueue
        #expect(CacheSettings(defaults: defaults).wifiLookahead == .entireQueue)
    }
}

import Foundation
import Observation
import OSLog
import SwiftSonic

/// Auto-caching for the queue: saves upcoming songs into the stream cache before they play, so
/// playback carries on through a dead zone. On cellular it fetches the next few songs; on Wi-Fi it
/// works down the queue until the stream cache size limit. It starts only once the playing song
/// no longer needs the network, pauses near a track transition, and retries failed downloads.
/// Low Data Mode turns it off. Explicit downloads are untouched.
@MainActor
final class UpcomingSongsPrefetcher {
    nonisolated static let lookahead = 3
    nonisolated static let maximumAttempts = 5

    /// What to fetch for the current queue, network and settings. A new plan replaces the old one;
    /// an unchanged plan leaves a download in flight alone.
    struct Plan: Equatable {
        let serverID: UUID
        let songIDs: [String]
        let format: String?
        let maxBitRate: Int?
    }

    private let playerState: PlayerState
    private let server: any ServerServiceProtocol
    private let resolver: any MediaResolverProtocol
    private let cache: any AudioStreamCacheProtocol
    private let settings: CacheSettings
    private let streamSettings: StreamSettings
    private let session: URLSession
    private let settleDelay: Duration
    private let retryDelay: Duration
    private var observation: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var activePlan: Plan?
    private var protectedSongIDs: (serverID: UUID, songIDs: Set<String>)?

    init(playerState: PlayerState, server: any ServerServiceProtocol, resolver: any MediaResolverProtocol,
         cache: any AudioStreamCacheProtocol, settings: CacheSettings, streamSettings: StreamSettings,
         session: URLSession? = nil, settleDelay: Duration = .seconds(3), retryDelay: Duration = .seconds(2)) {
        self.playerState = playerState
        self.server = server
        self.resolver = resolver
        self.cache = cache
        self.settings = settings
        self.streamSettings = streamSettings
        self.settleDelay = settleDelay
        self.retryDelay = retryDelay
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 1800
            // Cellular is allowed; Low Data Mode is respected by never using a constrained path.
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = false
            self.session = URLSession(configuration: config)
        }
    }

    func start() {
        guard observation == nil else { return }
        let playerState = playerState, settings = settings, state = server.state
        observation = Task { [weak self] in
            let changes = Observations {
                (playerState.currentTrack?.id, playerState.currentIndex, playerState.queue.count,
                 playerState.currentSongNeedsNetwork, playerState.isNearTrackTransition,
                 settings.cacheUpcomingSongs, settings.wifiLookahead, settings.cellularLookahead, settings.cacheFormat,
                 state.isOnline, state.networkPathEvent.descriptor.isCellular,
                 state.networkPathEvent.descriptor.isConstrained, state.hasObservedNetworkPath)
            }
            for await _ in changes { self?.schedule() }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        work?.cancel()
        work = nil
        activePlan = nil
    }

    /// The songs to fetch: the next ones in the queue that come from the server. Nil is no limit.
    nonisolated static func candidates(queue: [DisplayableSong], currentIndex: Int, lookahead: Int? = lookahead) -> [DisplayableSong] {
        guard currentIndex >= 0, currentIndex + 1 < queue.count else { return [] }
        let upcoming = queue[(currentIndex + 1)...].filter { !$0.isLocalFile }
        return lookahead.map { Array(upcoming.prefix($0)) } ?? upcoming
    }

    /// How far ahead to cache right now, or nil to leave the network alone. Low Data Mode (a
    /// constrained path) stops it; Low Power Mode deliberately does not, because the cache is what
    /// keeps music going through a dead zone. The playing song's own download and the standby
    /// preload before a transition both come first.
    nonisolated static func lookahead(
        enabled: Bool,
        isOnline: Bool,
        hasObservedPath: Bool,
        path: NetworkPathDescriptor,
        wifi: CacheLookahead,
        cellular: CacheLookahead,
        currentSongNeedsNetwork: Bool,
        isNearTrackTransition: Bool,
        lowPowerMode: Bool
    ) -> CacheLookahead? {
        guard enabled, isOnline, hasObservedPath, !path.isConstrained,
              !currentSongNeedsNetwork, !isNearTrackTransition else { return nil }
        let lookahead = path.isCellular ? cellular : wifi
        return lookahead.isOff ? nil : lookahead
    }

    private func schedule() {
        updateProtectedSongs()
        let plan = makePlan()
        guard plan != activePlan else { return }
        activePlan = plan
        work?.cancel()
        work = nil
        guard let plan, !plan.songIDs.isEmpty else { return }
        let settleDelay = settleDelay
        work = Task { [weak self] in
            // Let the playing song settle into its buffer before the next downloads start.
            do { try await Task.sleep(for: settleDelay) } catch { return }
            await self?.prefetch(plan)
        }
    }

    private func makePlan() -> Plan? {
        let state = server.state
        guard let serverID = state.activeServer?.id,
              let lookahead = Self.lookahead(
                  enabled: settings.cacheUpcomingSongs,
                  isOnline: state.isOnline,
                  hasObservedPath: state.hasObservedNetworkPath,
                  path: state.networkPathEvent.descriptor,
                  wifi: settings.wifiLookahead,
                  cellular: settings.cellularLookahead,
                  currentSongNeedsNetwork: playerState.currentSongNeedsNetwork,
                  isNearTrackTransition: playerState.isNearTrackTransition,
                  lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
              ) else { return nil }
        let songs = Self.candidates(queue: playerState.queue, currentIndex: playerState.currentIndex, lookahead: lookahead.songLimit)
        let usesStreamFormat = settings.cacheFormat == .matchStream
        return Plan(
            serverID: serverID,
            songIDs: songs.map(\.id),
            format: usesStreamFormat ? streamSettings.currentQuality.subsonicFormat : settings.cacheFormat.subsonicFormat,
            maxBitRate: usesStreamFormat ? streamSettings.currentQuality.subsonicMaxBitRate : settings.cacheFormat.subsonicMaxBitRate
        )
    }

    /// Songs still ahead in the queue (and the playing one) are never evicted to make room.
    private func updateProtectedSongs() {
        guard let serverID = server.state.activeServer?.id else { return }
        let queue = playerState.queue
        let start = max(0, playerState.currentIndex)
        let songIDs = start < queue.count ? Set(queue[start...].filter { !$0.isLocalFile }.map(\.id)) : []
        guard protectedSongIDs?.serverID != serverID || protectedSongIDs?.songIDs != songIDs else { return }
        protectedSongIDs = (serverID, songIDs)
        let cache = cache
        Task { await cache.setProtectedSongIDs(songIDs, serverId: serverID) }
    }

    private func prefetch(_ plan: Plan) async {
        guard let connection = try? await server.activeConnection(),
              connection.version.serverID == plan.serverID else { return }
        let client = connection.makeSwiftSonicClient()
        let budget = await cache.maxBytes
        var plannedBytes = await cache.cachedBytes(forSongIds: Set(plan.songIDs), serverId: plan.serverID)
        var fetched: (count: Int64, bytes: Int64) = (0, 0)
        for songID in plan.songIDs {
            guard !Task.isCancelled else { return }
            guard let url = client.streamURL(id: songID, maxBitRate: plan.maxBitRate, format: plan.format) else { continue }
            let quality = CachedAudioQuality(streamURL: url)
            if await resolver.hasLocalCopy(songId: songID, serverId: plan.serverID, atLeast: quality) { continue }
            // Stop before the next song would push the queue's copies past the cache size limit.
            let estimate = fetched.count > 0 ? fetched.bytes / fetched.count : 0
            guard plannedBytes + estimate <= budget else {
                Logger.cache.info("Upcoming cache reached the size limit with \(plannedBytes) bytes queued")
                return
            }
            let request = PlayerService.cacheDownloadRequest(url: url, headers: connection.authorizationHeaders(for: url))
            guard let bytes = await download(songID: songID, request: request, quality: quality, serverID: plan.serverID) else {
                if Task.isCancelled { return }
                continue
            }
            plannedBytes += bytes
            fetched = (fetched.count + 1, fetched.bytes + bytes)
        }
    }

    /// Downloads one song, retrying failures that can change with backoff. Returns the stored size.
    private func download(songID: String, request: URLRequest, quality: CachedAudioQuality, serverID: UUID) async -> Int64? {
        for attempt in 1...Self.maximumAttempts {
            do {
                let (file, response) = try await session.download(for: request, delegate: OriginScopedRedirectDelegate())
                defer { try? FileManager.default.removeItem(at: file) }
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw CacheDownloadStatusError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                try AudioResponseValidator.validate(fileAt: file, response: response, songId: songID, logger: Logger.cache)
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
                _ = try await cache.store(fileAt: file, forSongId: songID, serverId: serverID,
                                          mimeType: response.mimeType ?? "audio/mpeg", quality: quality)
                Logger.cache.info("Auto-cached upcoming '\(songID, privacy: .public)'")
                return size
            } catch {
                if Task.isCancelled { return nil }
                Logger.cache.debug("Upcoming cache attempt \(attempt, privacy: .public) failed for '\(songID, privacy: .public)': \(error.logSafe, privacy: .public)")
                guard attempt < Self.maximumAttempts, CacheDownloadRetry.isRetryable(error) else { return nil }
                do {
                    try await Task.sleep(for: CacheDownloadRetry.delay(afterAttempt: attempt, base: retryDelay))
                } catch {
                    return nil
                }
            }
        }
        return nil
    }
}

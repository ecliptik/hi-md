import Foundation
import Observation
import OSLog
import SwiftSonic

/// Auto-caching for the queue: saves the next few songs into the stream cache while the current
/// one plays, so playback carries on through a dead zone. The stream cache keeps its own size
/// limit and can be cleared on its own; explicit downloads are untouched.
@MainActor
final class UpcomingSongsPrefetcher {
    nonisolated static let lookahead = 3

    private let playerState: PlayerState
    private let server: any ServerServiceProtocol
    private let resolver: any MediaResolverProtocol
    private let cache: any AudioStreamCacheProtocol
    private let settings: CacheSettings
    private let streamSettings: StreamSettings
    private let session: URLSession
    private var observation: Task<Void, Never>?
    private var work: Task<Void, Never>?

    init(playerState: PlayerState, server: any ServerServiceProtocol, resolver: any MediaResolverProtocol,
         cache: any AudioStreamCacheProtocol, settings: CacheSettings, streamSettings: StreamSettings) {
        self.playerState = playerState
        self.server = server
        self.resolver = resolver
        self.cache = cache
        self.settings = settings
        self.streamSettings = streamSettings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 1800
        config.allowsConstrainedNetworkAccess = false
        session = URLSession(configuration: config)
    }

    func start() {
        guard observation == nil else { return }
        let playerState = playerState, settings = settings, state = server.state
        observation = Task { [weak self] in
            let changes = Observations {
                (playerState.currentTrack?.id, playerState.queue.count, settings.cacheUpcomingSongs,
                 state.isOnline, state.networkPathEvent.descriptor.isExpensive)
            }
            for await _ in changes { self?.schedule() }
        }
    }

    /// The songs to fetch: the next few in the queue that come from the server.
    nonisolated static func candidates(queue: [DisplayableSong], currentIndex: Int, lookahead: Int = lookahead) -> [DisplayableSong] {
        guard currentIndex >= 0, currentIndex + 1 < queue.count else { return [] }
        return queue[(currentIndex + 1)...].filter { !$0.isLocalFile }.prefix(lookahead).map { $0 }
    }

    private func schedule() {
        work?.cancel()
        let path = server.state.networkPathEvent.descriptor
        guard settings.cacheUpcomingSongs, server.state.isOnline, server.state.hasObservedNetworkPath,
              !path.isConstrained, !path.isExpensive || settings.cacheOverCellular else { return }
        let songs = Self.candidates(queue: playerState.queue, currentIndex: playerState.currentIndex)
        guard !songs.isEmpty else { return }
        work = Task { [weak self] in
            // Let the current song's own stream start first.
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            await self?.prefetch(songs)
        }
    }

    private func prefetch(_ songs: [DisplayableSong]) async {
        guard let connection = try? await server.activeConnection() else { return }
        let serverID = connection.version.serverID
        let client = connection.makeSwiftSonicClient()
        let usesStreamFormat = settings.cacheFormat == .matchStream
        let policy = streamSettings.currentPolicy
        for song in songs {
            guard !Task.isCancelled else { return }
            if await resolver.localSource(songId: song.id, serverId: serverID) != nil { continue }
            let stream = policy.request(for: song.streamTraits)
            let format = usesStreamFormat ? stream.format : settings.cacheFormat.subsonicFormat
            let bitrate = usesStreamFormat ? stream.maxBitRate : settings.cacheFormat.subsonicMaxBitRate
            guard let url = client.streamURL(id: song.id, maxBitRate: bitrate, format: format) else { continue }
            let request = PlayerService.cacheDownloadRequest(
                url: url, headers: connection.authorizationHeaders(for: url), allowCellular: settings.cacheOverCellular
            )
            do {
                let (file, response) = try await session.download(for: request, delegate: OriginScopedRedirectDelegate())
                defer { try? FileManager.default.removeItem(at: file) }
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                try AudioResponseValidator.validate(fileAt: file, response: response, songId: song.id, logger: Logger.cache)
                _ = try await cache.store(fileAt: file, forSongId: song.id, serverId: serverID,
                                          mimeType: response.mimeType ?? "audio/mpeg")
                Logger.cache.info("Auto-cached upcoming '\(song.id, privacy: .public)'")
            } catch {
                if Task.isCancelled { return }
                Logger.cache.debug("Upcoming cache failed for '\(song.id, privacy: .public)': \(error, privacy: .public)")
                return
            }
        }
    }
}

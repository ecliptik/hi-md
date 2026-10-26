import Foundation
import Observation
import SwiftSonic
import OSLog

@Observable
@MainActor
final class OfflineFavoritesSync {
    struct Request: Equatable {
        let version: ServerConnection.Version?
        let account: ServerSnapshot?
        /// What the path is (Wi-Fi, cellular, constrained), not each path event: a re-evaluation
        /// of the same network, such as a VPN tunnel's, must not restart the run.
        let network: NetworkPathDescriptor
        let isOnline: Bool
        let observedNetwork: Bool
        let enabled: Bool
        let keepFavorites: Bool
        let keepRecentlyPlayed: Bool
        let keepPinned: Bool
        let allowsCellular: Bool
        let format: CacheFormat
        let streamPolicy: StreamQualityPolicy
        let revision: Int
    }

    private(set) var usage = OfflineFavoritesStore.Usage()
    private(set) var isSyncing = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var error: UserFacingError?
    var revision = 0

    private let store: OfflineFavoritesStore
    private let settings: CacheSettings
    private let streamSettings: StreamSettings
    private let server: any ServerServiceProtocol
    private let downloads: any DownloadServiceProtocol
    private let cache: any AudioStreamCacheProtocol
    private let artwork: ArtworkImageCache?
    private let transfer: OfflineFavoritesTransfer
    private let fetchFavorites: @Sendable (ServerConnection) async throws -> Starred2
    private let fetchAlbum: @Sendable (ServerConnection, String) async throws -> AlbumID3
    private let fetchPlaylist: @Sendable (ServerConnection, String) async throws -> PlaylistWithSongs
    /// Album IDs from Recently Played, most recent first.
    var recentAlbumIDs: @MainActor (UUID) async -> [String] = { _ in [] }
    /// Pinned albums and playlists for a server, as (kind, id) with kind "album" or "playlist".
    var pinnedItems: @MainActor (UUID) -> [(kind: String, id: String)] = { _ in [] }
    /// How many recently played albums auto-caching keeps.
    static let recentAlbumLimit = 12
    /// Songs saved, and albums looked up, at the same time.
    static let parallelTransfers = 3
    static let parallelLookups = 4
    private var runID = UUID()

    var request: Request {
        Request(version: server.state.activeConnectionVersion,
                account: server.state.activeServer,
                network: server.state.networkPathEvent.descriptor,
                isOnline: server.state.isOnline,
                observedNetwork: server.state.hasObservedNetworkPath,
                enabled: settings.keepsAnythingOffline,
                keepFavorites: settings.keepFavoritesOffline,
                keepRecentlyPlayed: settings.keepRecentlyPlayedOffline,
                keepPinned: settings.keepPinnedOffline,
                allowsCellular: settings.cacheOverCellular,
                format: settings.cacheFormat, streamPolicy: streamSettings.currentPolicy,
                revision: revision)
    }

    var waitingForConnection: Bool { !server.state.isOnline }
    var waitingForWiFi: Bool {
        let path = server.state.networkPathEvent.descriptor
        return !server.state.hasObservedNetworkPath || path.isConstrained
            || (path.isExpensive && !settings.cacheOverCellular)
    }

    init(store: OfflineFavoritesStore, settings: CacheSettings, streamSettings: StreamSettings,
         server: any ServerServiceProtocol, downloads: any DownloadServiceProtocol,
         cache: any AudioStreamCacheProtocol, artwork: ArtworkImageCache? = nil,
         session: URLSession? = nil,
         fetchFavorites: @escaping @Sendable (ServerConnection) async throws -> Starred2 = { try await $0.makeSwiftSonicClient().getStarred2() },
         fetchAlbum: @escaping @Sendable (ServerConnection, String) async throws -> AlbumID3 = { try await $0.makeSwiftSonicClient().getAlbum(id: $1) },
         fetchPlaylist: @escaping @Sendable (ServerConnection, String) async throws -> PlaylistWithSongs = { try await $0.makeSwiftSonicClient().getPlaylist(id: $1) }) {
        self.store = store
        self.settings = settings
        self.streamSettings = streamSettings
        self.server = server
        self.downloads = downloads
        self.cache = cache
        self.artwork = artwork
        transfer = OfflineFavoritesTransfer(session: session)
        self.fetchFavorites = fetchFavorites
        self.fetchAlbum = fetchAlbum
        self.fetchPlaylist = fetchPlaylist
    }

    func refreshUsage() async {
        if let value = try? await store.usage() { usage = value }
    }

    func synchronize() async {
        let id = UUID()
        runID = id
        let expected = request
        isSyncing = false
        error = nil
        completed = 0
        total = 0
        do {
            try check(expected)
            if !expected.enabled {
                try await store.clearAudio()
            } else if expected.version != nil, !waitingForConnection, !waitingForWiFi {
                isSyncing = true
                try await synchronize(expected)
            }
        } catch {
            if runID == id, !UserFacingError.isCancellation(error) {
                self.error = UserFacingError.from(error)
            }
        }
        guard runID == id else { return }
        isSyncing = false
        await refreshUsage()
    }

    private func synchronize(_ expected: Request) async throws {
        let connection = try await server.activeConnection()
        try check(expected)
        guard connection.version == expected.version,
              connection.server == expected.account
        else { throw CancellationError() }
        let serverID = connection.version.serverID
        let client = connection.makeSwiftSonicClient()
        let favorites = expected.keepFavorites ? try await fetchFavorites(connection) : nil
        try check(expected)
        var albums = try await lookUpAlbums((favorites?.album ?? []).map(\.id), connection: connection,
                                            expected: expected, required: true)
        var albumIDs = Set(albums.map(\.id))
        // Recently played and pinned items are best effort: one that was deleted on the server
        // is skipped rather than stopping the whole sync.
        if expected.keepRecentlyPlayed {
            let recent = await recentAlbumIDs(serverID).prefix(Self.recentAlbumLimit).filter { albumIDs.insert($0).inserted }
            albums += try await lookUpAlbums(recent, connection: connection, expected: expected, required: false)
        }
        var extraSongs: [Song] = []
        if expected.keepPinned {
            var pinnedAlbums: [String] = []
            for pin in pinnedItems(serverID) {
                if pin.kind == "album", albumIDs.insert(pin.id).inserted {
                    pinnedAlbums.append(pin.id)
                } else if pin.kind == "playlist" {
                    extraSongs += (try? await fetchPlaylist(connection, pin.id))?.entry ?? []
                    try check(expected)
                }
            }
            albums += try await lookUpAlbums(pinnedAlbums, connection: connection, expected: expected, required: false)
        }
        // Only a complete, successful catalogue may remove previously saved favorites.
        let songs = try await store.reconcile(favorites: favorites, albums: albums, extraSongs: extraSongs, serverID: serverID)
        try check(expected)
        // Only songs that still need saving count as progress, so a run with nothing to fetch
        // shows none.
        var pending: [Song] = []
        for song in songs where await store.localURL(songID: song.id, serverID: serverID) == nil {
            pending.append(song)
        }
        try check(expected)
        total = pending.count
        // A few songs at a time: one request after another left the link idle between songs.
        var start = 0
        while start < pending.count {
            let batch = Array(pending[start..<min(start + Self.parallelTransfers, pending.count)])
            start += batch.count
            try await withThrowingTaskGroup(of: Void.self) { group in
                for song in batch {
                    group.addTask { try await self.save(song, client: client, connection: connection, expected: expected) }
                }
                try await group.waitForAll()
            }
        }
        var covers = Set<String>()
        for song in songs {
            try check(expected)
            if let cover = song.coverArt, covers.insert(cover).inserted {
                _ = await artwork?.load(coverArtId: cover)
            }
        }
    }

    /// Looks up albums a few at a time. A required album that fails stops the sync; an optional
    /// one (recently played, pinned) is skipped.
    private func lookUpAlbums(_ ids: [String], connection: ServerConnection, expected: Request,
                              required: Bool) async throws -> [AlbumID3] {
        var albums: [AlbumID3] = []
        var start = 0
        while start < ids.count {
            let batch = Array(ids[start..<min(start + Self.parallelLookups, ids.count)])
            start += batch.count
            let fetch = fetchAlbum
            let found = try await withThrowingTaskGroup(of: (Int, AlbumID3?).self) { group in
                for (index, id) in batch.enumerated() {
                    group.addTask {
                        if required { return (index, try await fetch(connection, id)) }
                        return (index, try? await fetch(connection, id))
                    }
                }
                var results: [(Int, AlbumID3?)] = []
                for try await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
            }
            albums += found
            try check(expected)
        }
        return albums
    }

    /// Saves one song from Downloads, the stream cache or the server. A song removed from the
    /// server is skipped; other failures stop the run, and a later run resumes saved work.
    private func save(_ song: Song, client: SwiftSonicClient, connection: ServerConnection,
                      expected: Request) async throws {
        let serverID = connection.version.serverID
        try check(expected)
        do {
            if await store.localURL(songID: song.id, serverID: serverID) == nil {
                let manual = await downloads.downloadedURL(forSongId: song.id, serverId: serverID)
                let cached = manual == nil ? await cache.cachedURL(forSongId: song.id, serverId: serverID) : nil
                if let local = manual ?? cached {
                    try check(expected)
                    try await store.store(fileAt: local, songID: song.id, serverID: serverID)
                } else {
                    let stream = expected.streamPolicy.request(
                        for: StreamSourceTraits(suffix: song.suffix, bitRate: song.bitRate, channelCount: song.channelCount)
                    )
                    let format = expected.format == .matchStream ? stream.format : expected.format.subsonicFormat
                    let bitrate = expected.format == .matchStream ? stream.maxBitRate : expected.format.subsonicMaxBitRate
                    guard let url = client.streamURL(id: song.id, maxBitRate: bitrate, format: format) else {
                        throw UserFacingError.contentRemoved
                    }
                    let request = PlayerService.cacheDownloadRequest(
                        url: url, headers: connection.authorizationHeaders(for: url), allowCellular: expected.allowsCellular,
                        serviceType: .background
                    )
                    let file = try await transfer.download(request, songID: song.id)
                    defer { try? FileManager.default.removeItem(at: file) }
                    try check(expected)
                    try await store.store(fileAt: file, songID: song.id, serverID: serverID)
                }
            }
            try check(expected)
            completed += 1
        } catch {
            try check(expected)
            self.error = UserFacingError.from(error)
            // Stop on network/storage failures; a later reconnect or retry resumes saved work.
            if self.error != .contentRemoved { throw error }
        }
    }

    private func check(_ expected: Request) throws {
        try Task.checkCancellation()
        guard request == expected else { throw CancellationError() }
    }
}

private actor OfflineFavoritesTransfer {
    private let session: URLSession

    init(session: URLSession?) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 3600
            config.allowsConstrainedNetworkAccess = false
            self.session = URLSession(configuration: config)
        }
    }

    func download(_ request: URLRequest, songID: String) async throws -> URL {
        var request = request
        request.allowsExpensiveNetworkAccess = request.allowsCellularAccess
        request.allowsConstrainedNetworkAccess = false
        let (file, response) = try await session.download(for: request, delegate: OriginScopedRedirectDelegate())
        do {
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UserFacingError.downloadFailed
            }
            try AudioResponseValidator.validate(fileAt: file, response: response, songId: songID, logger: Logger.cache)
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}

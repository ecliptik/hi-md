import Foundation
import OSLog
import SwiftUI
import SwiftData
import SwiftSonic

@MainActor
final class AppContainer {
    let playerState: PlayerState
    let serverState: ServerState
    let playbackPreferences: PlaybackPreferences
    let cacheSettings: CacheSettings

    let modelContainer: ModelContainer
    let libraryIndexStore: LibraryIndexStore
    let libraryIndexMaintenance: LibraryIndexMaintenanceService
    let libraryCatalog: LibraryCatalog
    let keychainService: any KeychainServiceProtocol
    let serverService: any ServerServiceProtocol
    let libraryService: any LibraryServiceProtocol
    let localMusic: LocalMusicLibrary
    let offlineLibrary: OfflineBrowsingLibrary
    let offlineBrowsingReader: OfflineBrowsingReader
    let offlineFavoritesStore: OfflineFavoritesStore
    let offlineFavoritesSync: OfflineFavoritesSync
    let audioStreamCache: any AudioStreamCacheProtocol
    let downloadService: any DownloadServiceProtocol
    let downloadActivity = DownloadActivityState()
    let mediaResolver: any MediaResolverProtocol
    let playerService: any PlayerServiceProtocol
    let nowPlayingService: any NowPlayingServiceProtocol
    let favoritesService: any FavoritesServiceProtocol
    let pinService: any PinServiceProtocol
    let playlistService: any PlaylistServiceProtocol
    let radioService: any RadioServiceProtocol
    let toastService = ToastService()
    let networkMonitor: NetworkMonitor
    let playbackDiagnostics: PlaybackDiagnostics
    let sessionService: PlaybackSessionService
    let dominantColorExtractor = DominantColorExtractor()
    let artworkImageCache: ArtworkImageCache
    let statsService: StatsService
    private let _player: PlayerService
    let wrappedPlaylistService: WrappedPlaylistService
    let moodPlaylistService: MoodPlaylistService
    let lyricsSettings: LyricsSettings
    let lyricsService: LyricsService
    let trackSharingService: TrackSharingService
    let recommendationService: RecommendationService
    let listenBrainzService: ListenBrainzService
    let externalProvidersStore: ExternalProvidersStore
    let externalArtworkCache = ExternalArtworkCache()
    let externalArtistImageResolver = ExternalArtistImageResolver()
    let searchHistoryService: SearchHistoryService
    let replayGainSettings: ReplayGainSettings
    let crossfadeSettings: CrossfadeSettings
    let streamSettings: StreamSettings
    let lidarrSettings: LidarrSettings
    private var lifecycleTasks: [Task<Void, Never>] = []
    private(set) lazy var widgetArtwork = WidgetArtworkWriter(artworkImageCache: artworkImageCache)
    private(set) lazy var downloadActivities = DownloadActivityController(artwork: widgetArtwork)
    private(set) lazy var widgetSnapshotPublisher = WidgetSnapshotPublisher(
        playerState: playerState, serverState: serverState, modelContainer: modelContainer,
        moodPlaylistService: moodPlaylistService, artwork: widgetArtwork
    )
    /// Owned by `MinidiscRuntime`, so a link opened while launch is still building this container waits there.
    let linkRouter: LinkRouter
    #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
    private(set) lazy var watchBridge = PhoneWatchBridge(container: self)
    #endif
    private(set) lazy var aiRecommendationSettings = AIRecommendationSettings(keychain: keychainService)
    private(set) lazy var sleepTimer = SleepTimer(playerState: playerState, player: playerService)
    private(set) lazy var upcomingSongsPrefetcher = UpcomingSongsPrefetcher(
        playerState: playerState, server: serverService, resolver: mediaResolver,
        cache: audioStreamCache, settings: cacheSettings, streamSettings: streamSettings
    )
    /// Nil for in-memory test containers, which must not touch the device's Spotlight index.
    private(set) var spotlightIndexer: SpotlightIndexer?
    private let spotlightDefaults: UserDefaults?

    init(
        inMemory: Bool = false,
        playbackDiagnostics: PlaybackDiagnostics = PlaybackDiagnostics(),
        userDefaults: UserDefaults = .standard,
        linkRouter: LinkRouter = LinkRouter()
    ) throws {
        self.linkRouter = linkRouter
        let localStore = LocalMusicStore(directory: inMemory
            ? URL.temporaryDirectory.appendingPathComponent("minidisc-local-\(UUID())")
            : URL.applicationSupportDirectory.appendingPathComponent("minidisc-local-music"))
        localMusic = LocalMusicLibrary(store: localStore)
        serverState = ServerState(defaults: userDefaults)
        spotlightDefaults = inMemory ? nil : userDefaults
        let playbackPreferences = PlaybackPreferences(defaults: userDefaults)
        self.playbackPreferences = playbackPreferences
        playerState = PlayerState(isAutoExtendEnabled: playbackPreferences.isAutoExtendEnabled)
        cacheSettings = CacheSettings(defaults: userDefaults)
        externalProvidersStore = ExternalProvidersStore(defaults: userDefaults)
        replayGainSettings = ReplayGainSettings(defaults: userDefaults)
        crossfadeSettings = CrossfadeSettings(defaults: userDefaults)
        streamSettings = StreamSettings(defaults: userDefaults)
        lyricsSettings = LyricsSettings(defaults: userDefaults)
        self.playbackDiagnostics = playbackDiagnostics
        networkMonitor = NetworkMonitor(playbackDiagnostics: playbackDiagnostics)
        modelContainer = try ModelContainer.minidisc(inMemory: inMemory)
        let libraryIndexContainer = try ModelContainer.libraryIndex(inMemory: inMemory)
        let indexStore = LibraryIndexStore(modelContainer: libraryIndexContainer)
        libraryIndexStore = indexStore
        sessionService = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: inMemory))

        let keychain = KeychainService()
        keychainService = keychain
        lidarrSettings = LidarrSettings(keychain: keychain, defaults: userDefaults)

        let favoritesStore = OfflineFavoritesStore(directory: inMemory
            ? URL.temporaryDirectory.appendingPathComponent("minidisc-favorites-\(UUID())")
            : URL.applicationSupportDirectory.appendingPathComponent("minidisc-offline-favorites"))
        offlineFavoritesStore = favoritesStore
        let cache = AudioStreamCache(modelContainer: modelContainer, maxBytes: cacheSettings.capacityBytes, offlineFavorites: favoritesStore)
        audioStreamCache = cache

        let stats = StatsService(modelContainer: modelContainer)
        statsService = stats

        let server = ServerService(
            state: serverState,
            keychain: keychain,
            modelContainer: modelContainer,
            audioStreamCache: cache,
            libraryIndexStore: indexStore,
            playbackDiagnostics: playbackDiagnostics,
            compatibility: inMemory ? nil : NavidromeCompatibility(
                modelContainer: modelContainer, sessionService: sessionService,
                indexStore: indexStore, defaults: userDefaults
            ),
            offlineFavorites: favoritesStore
        )
        serverService = server
        trackSharingService = TrackSharingService(serverService: server)
        let librarySource = SwiftSonicLibrarySource(serverService: server)
        let librarySynchronizer = LibraryIndexSynchronizer(source: librarySource, store: indexStore)
        let catalog = LibraryCatalog(
            source: librarySource,
            store: indexStore,
            synchronizer: librarySynchronizer
        )
        libraryCatalog = catalog
        lyricsService = LyricsService(serverService: server, modelContainer: modelContainer)
        wrappedPlaylistService = WrappedPlaylistService(serverService: server, statsService: stats)
        radioService = RadioService(serverService: server)

        let download = DownloadService(serverService: server, modelContainer: modelContainer, toastService: toastService,
                                       transferTransport: inMemory ? nil : BackgroundDownloadTransport.shared, diagnostics: playbackDiagnostics)
        downloadService = download
        let offlineReader = OfflineBrowsingReader(models: modelContainer, downloads: download, cache: cache,
                                                  favorites: favoritesStore, index: indexStore)
        offlineBrowsingReader = offlineReader
        offlineLibrary = OfflineBrowsingLibrary(state: serverState, reader: offlineReader)

        let library = LibraryService(
            serverService: server,
            modelContainer: modelContainer,
            downloadService: download,
            statsService: stats,
            catalog: catalog,
            indexStore: indexStore,
            offlineFavorites: favoritesStore,
            offlineReader: offlineReader
        )
        libraryService = library
        libraryIndexMaintenance = LibraryIndexMaintenanceService(
            serverService: server,
            store: indexStore,
            synchronizer: librarySynchronizer,
            libraryService: library
        )

        artworkImageCache = ArtworkImageCache(downloadService: download, libraryService: library)
        artworkImageCache.localArtworkProvider = { id in await localStore.artwork(id) }
        artworkImageCache.persistCoversEnabled = cacheSettings.cacheArtwork
        offlineFavoritesSync = OfflineFavoritesSync(
            store: favoritesStore, settings: cacheSettings, streamSettings: streamSettings,
            server: server, downloads: download, cache: cache, artwork: artworkImageCache
        )
        offlineFavoritesSync.recentAlbumIDs = { serverID in
            await HomeFeedCache.shared.load(serverID: serverID)?.recentlyPlayed.map(\.id) ?? []
        }
        let moodCovers: @Sendable (PlaylistGradientSpec, String, String) async -> Void = { [artworkImageCache] spec, playlistId, title in
            let manager = await PlaylistCoverManager(
                downloadService: download,
                artworkImageCache: artworkImageCache
            )
            await manager.applyGradientCover(spec, playlistId: playlistId, title: title, coverArtId: nil)
        }
        moodPlaylistService = MoodPlaylistService(
            serverService: server,
            serverState: serverState,
            libraryService: library,
            catalog: catalog,
            coverApplier: moodCovers
        )

        let resolver = MediaResolver(
            downloadService: download,
            audioStreamCache: cache,
            serverService: server,
            serverState: serverState,
            streamSettings: streamSettings
        )
        mediaResolver = resolver

        let lbClient = ListenBrainzClient(transport: URLSessionListenBrainzTransport())
        let lb = ListenBrainzService(client: lbClient, keychain: keychain)
        listenBrainzService = lb

        let audioEngine: AudioEngine = AVPlayerEngine()
        let player = PlayerService(
            state: playerState,
            mediaResolver: resolver,
            serverService: server,
            sessionService: sessionService,
            artworkImageCache: artworkImageCache,
            libraryService: library,
            audioStreamCache: cache,
            downloadService: download,
            cacheSettings: cacheSettings,
            playbackPreferences: playbackPreferences,
            replayGainSettings: replayGainSettings,
            crossfadeSettings: crossfadeSettings,
            initialCrossfadeConfig: crossfadeSettings.config,
            toastService: toastService,
            statsService: stats,
            listenBrainzService: lb,
            playbackDiagnostics: playbackDiagnostics,
            engine: audioEngine,
            localMusicStore: localStore
        )
        _player = player
        playerService = player

        let nowPlayingPresenter = NowPlayingCenterPresenter()
        nowPlayingPresenter.entityScope = { [serverState] in
            serverState.activeServer.map { MusicIntentID.scope(baseURL: $0.baseURL, username: $0.username) }
        }
        let nowPlaying = NowPlayingService(
            playerService: player,
            artworkImageCache: artworkImageCache,
            presenter: nowPlayingPresenter
        )
        nowPlayingService = nowPlaying

        favoritesService = FavoritesService(libraryService: library, serverState: serverState, modelContainer: modelContainer)
        let pin = PinService(modelContainer: modelContainer)
        pinService = pin
        let playlist = PlaylistService(
            serverService: server,
            modelContainer: modelContainer,
            downloadService: download,
            libraryCatalog: catalog
        )
        playlistService = playlist

        let subsonicProvider = SubsonicRecommendationProvider(libraryService: library)
        let lbProvider = ListenBrainzRecommendationProvider(client: lbClient, service: lb, libraryService: library)
        recommendationService = RecommendationService(providers: [lbProvider, subsonicProvider])

        searchHistoryService = SearchHistoryService(container: modelContainer)

        lifecycleTasks = [
            Task { [download, downloadActivity, offlineLibrary] in
                var previousIDs = Set<String>()
                for await transfers in download.progressStream {
                    guard !Task.isCancelled else { break }
                    downloadActivity.transfers = transfers
                    let ids = Set(transfers.map { "\($0.serverId):\($0.songId)" })
                    if ids != previousIDs { offlineLibrary.revision += 1; previousIDs = ids }
                }
            },
            Task { [playlist] in
                guard !Task.isCancelled else { return }
                await playlist.retryMissingPlaylistDownloads()
            },
            Task { [lb] in
                guard !Task.isCancelled else { return }
                await lb.loadPersistedState()
            },
            Task { [lidarrSettings] in
                guard !Task.isCancelled else { return }
                await lidarrSettings.loadPersistedState()
            },
            Task { [externalArtworkCache] in
                guard !Task.isCancelled else { return }
                await externalArtworkCache.runGarbageCollection()
            },
            // The one memory-warning observer for the in-memory image caches.
            Task { [artworkImageCache] in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                    guard !Task.isCancelled else { break }
                    artworkImageCache.trimForMemoryWarning()
                    LidarrImageStore.shared.removeAll()
                }
            },
        ]
    }

    isolated deinit {
        lifecycleTasks.forEach { $0.cancel() }
        networkMonitor.stop()
    }

    /// Awaited by MinidiscApp's `.task` before the UI appears, ensuring
    /// PlayerService→NowPlayingService wiring is complete before any user
    /// interaction is possible.
    func setup() async {
        await _player.setNowPlayingService(nowPlayingService)
        await nowPlayingService.setFavoritesService(favoritesService)
        await _player.crossfadeSettingsDidChange()
        if let downloads = downloadService as? DownloadService {
            await downloads.setActivityReporter(downloadActivities)
        }
        WidgetCommandRelay.shared.handler = { [weak self] command in
            try await self?.handleWidgetCommand(command)
        }
        widgetSnapshotPublisher.start()
        offlineFavoritesSync.pinnedItems = { [modelContainer] serverID in
            let pins = FetchDescriptor<PinnedItem>(predicate: #Predicate { $0.serverId == serverID },
                                                   sortBy: [SortDescriptor(\.sortOrder)])
            return ((try? modelContainer.mainContext.fetch(pins)) ?? []).map { (kind: $0.itemType, id: $0.itemId) }
        }
        upcomingSongsPrefetcher.start()
        #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
        watchBridge.start()
        #endif
        // Loading the settings sends the saved equalizer curve to the audio taps.
        EqualizerSettings.shared.publish()
        if let spotlightDefaults, spotlightIndexer == nil {
            spotlightIndexer = SpotlightIndexer(serverState: serverState, store: libraryIndexStore, defaults: spotlightDefaults)
        }
        spotlightIndexer?.start()
    }

    func makePlaybackDiagnosticsReport() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return playbackDiagnostics.makeReport(
            context: PlaybackDiagnostics.ReportContext(
                appVersion: version,
                appBuild: build,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                playbackStatus: PlaybackDiagnostics.PlaybackStatus(playerState.playbackState),
                isPlaybackAvailable: playerState.isPlaybackAvailable,
                networkPath: PlaybackDiagnostics.NetworkPath(serverState.networkPathEvent),
                connectionVersion: serverState.activeConnectionVersion
            )
        )
    }

    /// Keeps deliberate long-lived startup work owned by the service graph so it
    /// can be cancelled if the graph is ever replaced or torn down.
    func retainLifecycleTask(_ task: Task<Void, Never>) {
        lifecycleTasks.append(task)
    }
}

// MARK: - ModelContainer factory

extension ModelContainer {
    /// Creates the Minidisc ModelContainer.
    /// - Parameter inMemory: Pass `true` in tests — Swift Testing parallelises tests,
    ///   so each test must create its own in-memory container (never shared).
    /// - Parameter url: Stores the database at a specific location instead of the default one.
    static func minidisc(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MinidiscSchemaV1.self)
        let config: ModelConfiguration
        if let url, !inMemory {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: MinidiscMigrationPlan.self,
            configurations: config
        )
    }

    /// Keeps frequent position saves out of the main SwiftData observation graph.
    /// The legacy main-store model remains registered for migration compatibility.
    /// - Parameter inMemory: Pass `true` in tests.
    static func session(inMemory: Bool = false) throws -> ModelContainer {
        // Adding a model to this unversioned store is a lightweight migration.
        let schema = Schema([PlaybackSession.self, PlaybackSessionContext.self])
        let config = ModelConfiguration("minidisc-session", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// A discardable metadata index kept separate from downloads, playback history,
    /// and server configuration so rebuilding it cannot affect user-owned local data.
    static func libraryIndex(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibraryIndexSchemaV3.self)
        let config = ModelConfiguration(
            "minidisc-library-index",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: LibraryIndexMigrationPlan.self,
            configurations: config
        )
    }
}

// MARK: - Cover art cache invalidation

extension AppContainer {
    private static let coverArtCacheVersionKey = "minidisc.coverArtCacheVersion"
    private static let currentCoverArtCacheVersion = 5

    /// Invalidates older artwork tiers so full-resolution files cannot bypass thumbnail decoding.
    static func invalidateCoverArtCacheIfNeeded(artworkCache: ArtworkImageCache) async {
        let stored = UserDefaults.standard.integer(forKey: coverArtCacheVersionKey)
        guard stored < currentCoverArtCacheVersion else { return }

        artworkCache.clearCache()
        artworkCache.clearRevalidationMetadata()
        await removeCoverArtFiles()

        UserDefaults.standard.set(currentCoverArtCacheVersion, forKey: coverArtCacheVersionKey)
        Logger.player.info("ArtworkImageCache: invalidated cover art disk cache (version \(stored) → \(currentCoverArtCacheVersion))")
    }

    /// A large cover folder takes a while to delete, so launch does it off the main thread.
    @concurrent
    private nonisolated static func removeCoverArtFiles() async {
        let coverArtsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.minidisc/coverarts")
        try? FileManager.default.removeItem(at: coverArtsDir)
        try? FileManager.default.createDirectory(at: coverArtsDir, withIntermediateDirectories: true)
        URLCache.shared.removeAllCachedResponses()
    }
}

// MARK: - Legacy cover art sweep

extension AppContainer {
    private static let artworkLegacySweepKey = "minidisc.artworkLegacySweep_v2"

    /// Removes legacy artwork files without @thumb or @hero suffixes.
    @discardableResult
    static func sweepLegacyCoverArtFiles() -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: artworkLegacySweepKey) else { return nil }

        return Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let coverArtsDir = docs.appendingPathComponent("app.minidisc/coverarts", isDirectory: true)

            guard let items = try? fm.contentsOfDirectory(at: coverArtsDir, includingPropertiesForKeys: nil) else { return }

            var deletedCount = 0
            for fileURL in items {
                guard !Task.isCancelled else { return }
                let name = fileURL.lastPathComponent
                guard !name.contains("@thumb") && !name.contains("@hero") else { continue }
                do {
                    try fm.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    Logger.artworkCache.warning("[SWEEP] Failed to delete legacy cover '\(name, privacy: .public)': \(error, privacy: .public)")
                }
            }

            await MainActor.run {
                UserDefaults.standard.set(true, forKey: artworkLegacySweepKey)
            }
            Logger.artworkCache.info("[SWEEP] Legacy cover art sweep complete: \(deletedCount) files deleted")
        }
    }
}

// MARK: - Audio extension migration

extension AppContainer {
    private nonisolated static let audioExtMigrationKey = "minidisc.audioExtMigration_v1"

    /// Repairs downloads saved as .mpeg: AVPlayer treats that extension as video, not MP3.
    /// Clears the stream cache and updates downloaded file paths after renaming.
    /// Runs on a background context, off the main thread, since it reads every downloaded track.
    @concurrent
    nonisolated static func migrateAudioExtensionsIfNeeded(
        modelContainer: ModelContainer,
        audioStreamCache: any AudioStreamCacheProtocol
    ) async {
        guard !UserDefaults.standard.bool(forKey: audioExtMigrationKey) else { return }

        await audioStreamCache.clearAll()
        Logger.migration.info("[ExtMigration] Ephemeral audio cache cleared")

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docs.appendingPathComponent("app.minidisc/downloads", isDirectory: true)

        let ctx = ModelContext(modelContainer)
        let tracks = (try? ctx.fetch(FetchDescriptor<DownloadedTrack>())) ?? []

        var renamedCount = 0
        var skippedCount = 0

        for track in tracks {
            guard track.filePath.hasSuffix(".mpeg") else { continue }
            // The suffix comes from the server, so only a known audio extension may rename the file.
            let desiredExt: String
            if let s = SafeFileName.audioExtension(track.suffix) {
                desiredExt = s
            } else {
                desiredExt = Self.audioExtFromMime(track.mimeType)
            }
            guard desiredExt != "mpeg" else { continue }

            let oldPath = track.filePath
            let newPath = String(oldPath.dropLast(".mpeg".count)) + ".\(desiredExt)"
            guard let oldURL = SafeFileName.url(forRelativePath: oldPath, in: downloadsDir),
                  let newURL = SafeFileName.url(forRelativePath: newPath, in: downloadsDir) else {
                Logger.migration.warning("[ExtMigration] Path outside the downloads folder, skipping: '\(oldPath, privacy: .public)'")
                skippedCount += 1
                continue
            }

            guard FileManager.default.fileExists(atPath: oldURL.path) else {
                Logger.migration.warning("[ExtMigration] File missing, skipping: '\(oldPath, privacy: .public)'")
                skippedCount += 1
                continue
            }
            do {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try FileManager.default.removeItem(at: newURL)
                }
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                track.filePath = newPath
                renamedCount += 1
                Logger.migration.info("[ExtMigration] '\(oldPath, privacy: .public)' → '\(newPath, privacy: .public)'")
            } catch {
                Logger.migration.error("[ExtMigration] Rename failed '\(oldPath, privacy: .public)': \(error, privacy: .public)")
                skippedCount += 1
            }
        }

        try? ctx.save()
        UserDefaults.standard.set(true, forKey: audioExtMigrationKey)
        Logger.migration.info("[ExtMigration] Complete: \(renamedCount) renamed, \(skippedCount) skipped")
    }

    // v2 completed prematurely on empty download stores. Reset the marker and retry counter together.
    private nonisolated static let m4aFaststartMigrationKey = "minidisc.m4aFaststartMigration_v3"
    private nonisolated static let m4aFaststartAttemptsKey = "minidisc.m4aFaststartMigration_v3_attempts"
    private nonisolated static let m4aFaststartMaxAttempts = 3

    /// Remuxes downloaded M4A files with trailing moov atoms. Detects the container from its bytes.
    /// Updates file sizes and marks completion only after a successful save with no failed remuxes.
    /// Failed passes retry on later launches up to m4aFaststartMaxAttempts.
    /// Like the extension repair, it reads and remuxes files off the main thread.
    @concurrent
    nonisolated static func migrateM4AFaststartIfNeeded(modelContainer: ModelContainer) async {
        guard !UserDefaults.standard.bool(forKey: m4aFaststartMigrationKey) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docs.appendingPathComponent("app.minidisc/downloads", isDirectory: true)

        let ctx = ModelContext(modelContainer)
        let tracks = (try? ctx.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
        let remuxer = AudioFaststartRemuxer()

        var remuxedCount = 0
        var failedCount = 0
        var m4aCount = 0
        for track in tracks {
            let fileURL = downloadsDir.appendingPathComponent(track.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            // Content sniff, not extension — catches a container with a wrong/renamed extension.
            guard AudioFaststartRemuxer.isM4AContainer(atPath: fileURL.path) else { continue }
            m4aCount += 1
            switch await remuxer.remuxToFaststartIfNeeded(at: fileURL) {
            case .remuxed:
                // Bytes changed — refresh fileSize from the remuxed file (?? 0 mirrors the
                // download path, where downloadedURL's `== 0` escape tolerates a read miss).
                let newSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                track.fileSize = newSize
                remuxedCount += 1
                Logger.migration.info("[M4AFaststart] faststart-remuxed '\(track.songId, privacy: .public)'")
            case .failed:
                failedCount += 1
                Logger.migration.warning("[M4AFaststart] export failed '\(track.songId, privacy: .public)' — will retry next boot")
            case .skipped:
                break
            }
        }

        // Persist the fileSize updates; only mark done on a clean pass so failures are retried.
        var saveOK = true
        do {
            try ctx.save()
        } catch {
            saveOK = false
            Logger.migration.error("[M4AFaststart] save failed: \(error, privacy: .public) — not marking done, will retry")
        }

        let attempts = UserDefaults.standard.integer(forKey: m4aFaststartAttemptsKey) + 1
        UserDefaults.standard.set(attempts, forKey: m4aFaststartAttemptsKey)
        let giveUp = attempts >= m4aFaststartMaxAttempts
        if saveOK && (failedCount == 0 || giveUp) {
            UserDefaults.standard.set(true, forKey: m4aFaststartMigrationKey)
            if failedCount > 0 {
                Logger.migration.warning("[M4AFaststart] giving up after \(attempts) attempts with \(failedCount) still failing")
            }
        }
        Logger.migration.info("[M4AFaststart] Complete: \(remuxedCount) remuxed, \(failedCount) failed of \(m4aCount) m4a (\(tracks.count) total), attempt \(attempts)")
    }

    private nonisolated static func audioExtFromMime(_ mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3":        return "mp3"
        case "audio/flac", "audio/x-flac":     return "flac"
        case "audio/mp4", "audio/m4a":         return "m4a"
        case "audio/aac", "audio/x-aac", "audio/aacp": return "aac"
        case "audio/ogg":                       return "ogg"
        case "audio/opus":                      return "opus"
        case "audio/wav", "audio/x-wav":       return "wav"
        case "audio/aiff", "audio/x-aiff":     return "aiff"
        default:                                return "mpeg"
        }
    }
}

// MARK: - SwiftUI environment key

private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}

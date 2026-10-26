import Foundation
import OSLog
import SwiftData

extension AppContainer {
    /// Builds the service graph and runs the launch work the iOS and Mac apps share. Each app
    /// adds its own platform work, such as scheduling background tasks, after this returns.
    static func launch(
        diagnostics: PlaybackDiagnostics,
        backgroundSync: BackgroundSyncCoordinator
    ) async throws -> AppContainer {
        let newContainer = try AppContainer(playbackDiagnostics: diagnostics)
        await newContainer.setup()
        // Detect an upgraded Navidrome before any cache maintenance or queue
        // restoration reads resource IDs from the local stores.
        await newContainer.serverService.loadPersistedState()
        // Start reachability before the UI is interactive so serverState.isOnline
        // is corrected from its optimistic default before any view loads data.
        newContainer.networkMonitor.start(
            serverState: newContainer.serverState,
            streamSettings: newContainer.streamSettings,
            playerService: newContainer.playerService,
            serverProbe: { [serverService = newContainer.serverService] in
                await ServerReachability.probe(serverService)
            }
        )
        await newContainer.nowPlayingService.start()
        AppContainer.invalidateCoverArtCacheIfNeeded(artworkCache: newContainer.artworkImageCache)
        if let sweepTask = AppContainer.sweepLegacyCoverArtFiles() {
            newContainer.retainLifecycleTask(sweepTask)
        }
        let modelContainer = newContainer.modelContainer
        let audioStreamCache = newContainer.audioStreamCache
        newContainer.retainLifecycleTask(Task { [modelContainer, audioStreamCache] in
            await AppContainer.migrateAudioExtensionsIfNeeded(
                modelContainer: modelContainer,
                audioStreamCache: audioStreamCache
            )
        })
        newContainer.retainLifecycleTask(Task { [modelContainer] in
            await AppContainer.migrateM4AFaststartIfNeeded(modelContainer: modelContainer)
        })
        await newContainer.playerService.restoreSession()
        let downloadService = newContainer.downloadService
        newContainer.retainLifecycleTask(Task { [modelContainer, downloadService] in
            await runCoverArtGarbageCollection(
                modelContainer: modelContainer,
                downloadService: downloadService
            )
        })
        await backgroundSync.configure(
            wrappedService: newContainer.wrappedPlaylistService,
            moodService: newContainer.moodPlaylistService,
            serverState: newContainer.serverState
        )
        // Cold start and BGProcessing share one deduplicated coordinator run.
        newContainer.retainLifecycleTask(Task {
            _ = await BackgroundActivity.run("playlist-sync") {
                await backgroundSync.run(calendar: .current)
            }
        })
        return newContainer
    }

    // MARK: - Cover art garbage collection

    @MainActor
    private static func runCoverArtGarbageCollection(
        modelContainer: ModelContainer,
        downloadService: any DownloadServiceProtocol
    ) async {
        let context = modelContainer.mainContext
        var referencedIds: Set<String> = []

        let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
        for album in albums {
            if let id = album.coverArtId { referencedIds.insert(id) }
        }

        let tracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
        for track in tracks {
            if let id = track.coverArtId { referencedIds.insert(id) }
        }

        let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
        for playlist in playlists {
            if let id = playlist.coverArtId { referencedIds.insert(id) }
        }

        let pinned = (try? context.fetch(FetchDescriptor<PinnedItem>())) ?? []
        for item in pinned {
            if let id = item.coverArtId { referencedIds.insert(id) }
        }

        await downloadService.garbageCollectOrphanedCovers(referencedIds: referencedIds)
    }
}

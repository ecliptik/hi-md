import Foundation
import Observation
import OSLog
import SwiftData
import SwiftSonic
import WidgetKit

/// Keeps the widgets' snapshot current: the playing song, recently played albums, pins and Moods.
///
/// Widgets and controls only reload when the snapshot actually changes, which keeps them well
/// inside WidgetKit's refresh budget.
@MainActor
final class WidgetSnapshotPublisher {
    private let playerState: PlayerState
    private let serverState: ServerState
    private let modelContainer: ModelContainer
    private let moodPlaylistService: MoodPlaylistService
    private let artwork: WidgetArtworkWriter
    private var lastPublished: WidgetSnapshot?
    private var pending: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []

    init(playerState: PlayerState, serverState: ServerState, modelContainer: ModelContainer,
         moodPlaylistService: MoodPlaylistService, artwork: WidgetArtworkWriter) {
        self.playerState = playerState
        self.serverState = serverState
        self.modelContainer = modelContainer
        self.moodPlaylistService = moodPlaylistService
        self.artwork = artwork
    }

    func start() {
        guard tasks.isEmpty else { return }
        let playerState = playerState, serverState = serverState
        tasks.append(Task { [weak self] in
            let changes = Observations {
                (playerState.currentTrack?.id, playerState.playbackState == .playing, serverState.activeServer?.id)
            }
            for await _ in changes { self?.setNeedsPublish() }
        })
        for name in [Notification.Name.minidiscMoodPlaylistsChanged, .minidiscPlaylistsChanged, .minidiscOfflineLibraryChanged] {
            tasks.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) { self?.setNeedsPublish() }
            })
        }
    }

    /// Coalesces bursts of changes, such as a skip followed by its play state, into one write.
    func setNeedsPublish() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await self?.publish()
        }
    }

    func publish() async {
        let snapshot = await makeSnapshot()
        guard snapshot != lastPublished else { return }
        do {
            try WidgetSnapshotStore.save(snapshot)
        } catch {
            Logger.ui.debug("Could not save the widget snapshot: \(error, privacy: .public)")
            return
        }
        let referenced = Set(([snapshot.nowPlaying?.artworkFile] + (snapshot.recentlyPlayed + snapshot.pinned).map(\.artworkFile)).compactMap { $0 })
        artwork.prune(keeping: referenced)
        lastPublished = snapshot
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    private func makeSnapshot() async -> WidgetSnapshot {
        var snapshot = WidgetSnapshot()
        if let track = playerState.currentTrack {
            snapshot.nowPlaying = WidgetSnapshot.Track(
                title: track.title,
                artist: track.artist ?? "",
                artworkFile: await artwork.file(for: track.coverArtId ?? track.id),
                isPlaying: playerState.playbackState == .playing || playerState.playbackState == .loading
            )
        }
        guard let server = serverState.activeServer else { return snapshot }
        snapshot.hasServer = true

        if let feed = await HomeFeedCache.shared.load(serverID: server.id) {
            for album in feed.recentlyPlayed.prefix(12) {
                snapshot.recentlyPlayed.append(WidgetSnapshot.Collection(
                    id: album.id, kind: .album, title: album.name, subtitle: album.artist,
                    coverArtId: album.coverArt, artworkFile: await artwork.file(for: album.coverArt)
                ))
            }
        }

        let serverID = server.id
        var pins = FetchDescriptor<PinnedItem>(predicate: #Predicate { $0.serverId == serverID },
                                               sortBy: [SortDescriptor(\.sortOrder)])
        pins.fetchLimit = 12
        for pin in (try? modelContainer.mainContext.fetch(pins)) ?? [] {
            guard let kind = WidgetSnapshot.Collection.Kind(rawValue: pin.itemType) else { continue }
            snapshot.pinned.append(WidgetSnapshot.Collection(
                id: pin.itemId, kind: kind, title: pin.displayName, subtitle: pin.displaySubtitle,
                coverArtId: pin.coverArtId, artworkFile: await artwork.file(for: pin.coverArtId)
            ))
        }

        let serverKey = server.id.uuidString
        for mood in Mood.allCases {
            let available = await moodPlaylistService.playlistId(for: mood, serverId: serverKey) != nil
            snapshot.moods.append(WidgetSnapshot.MoodEntry(
                id: mood.rawValue, title: String(localized: mood.title), symbolName: mood.symbolName, isAvailable: available
            ))
        }
        return snapshot
    }
}

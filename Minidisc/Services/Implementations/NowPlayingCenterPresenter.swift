#if os(iOS) && canImport(NowPlaying)
import AppIntents
import Foundation
import NowPlaying
import OSLog
import UIKit

/// What the system shows for Minidisc on the Lock Screen, in Control Center, in the Dynamic Island
/// and in CarPlay. A `MediaSession` observes this model, so changing it is the whole update.
@MainActor
@Observable
final class NowPlayingSessionModel: MediaSessionRepresentable {
    nonisolated let id = "app.minidisc.player"
    var content: (any MediaContentRepresentable)?
    var playbackSnapshot: MediaPlaybackSnapshot?
    var commands: [MediaCommand] = []
}

/// Translates playback snapshots into the iOS 27 NowPlaying framework.
///
/// The interface matches the MediaPlayer-based presenter it replaced, so `NowPlayingService` and
/// `PlayerService` send the same updates at the same moments, including the hand-off between the
/// engine's two decks during gapless playback and crossfades.
@MainActor
final class NowPlayingCenterPresenter {
    let model = NowPlayingSessionModel()
    private var session: MediaSession<NowPlayingSessionModel>?
    private var contentGeneration: UInt64 = 0
    private var current: NowPlayingSnapshot?
    private var duration: TimeInterval = 0
    private var artworkData: Data?
    private weak var playerService: (any PlayerServiceProtocol)?
    private var likeAction: (@Sendable () async -> Void)?
    private var isLiveStream = false
    private var canFavorite = false
    private var isFavorite = false

    /// Identifies the active server and account for Siri entity IDs; nil without a server.
    var entityScope: @MainActor () -> String? = { nil }

    func start(
        playerService: any PlayerServiceProtocol,
        likeAction: @escaping @Sendable () async -> Void
    ) {
        guard session == nil else { return }
        self.playerService = playerService
        self.likeAction = likeAction
        rebuildCommands()
        let session = MediaSession(model)
        self.session = session
        Task {
            do { try await session.requestToBecomeApplicationPrimary() }
            catch { Logger.nowPlaying.warning("Now Playing session did not become primary: \(error, privacy: .public)") }
        }
    }

    func shutdown() {
        model.content = nil
        model.playbackSnapshot = nil
        model.commands = []
        session = nil
        clearRelevantEntities()
    }

    func clear(generation: UInt64) {
        guard generation >= contentGeneration else { return }
        contentGeneration = generation
        current = nil
        artworkData = nil
        model.content = nil
        model.playbackSnapshot = nil
        clearRelevantEntities()
    }

    func setBaseInfo(for snapshot: NowPlayingSnapshot, generation: UInt64) {
        guard generation >= contentGeneration else { return }
        contentGeneration = generation
        // The next song on the same album keeps its cover through the change, instead of
        // publishing a song with no artwork and then the same artwork again, which the Dynamic
        // Island and Lock Screen sometimes never redraw.
        let keepsCover = !snapshot.isLiveStream && snapshot.coverArtId != nil
            && snapshot.coverArtId == current?.coverArtId && current?.isLiveStream == false
        current = snapshot
        duration = snapshot.duration
        if !keepsCover { artworkData = nil }
        rebuildContent()
        model.playbackSnapshot = Self.playbackSnapshot(position: snapshot.position, rate: snapshot.playbackRate)
        publishRelevantEntity(for: snapshot)
    }

    func mergePosition(
        elapsed: TimeInterval,
        rate: Float,
        duration: TimeInterval,
        generation: UInt64
    ) {
        guard generation == contentGeneration else { return }
        if duration != self.duration {
            self.duration = duration
            rebuildContent()
        }
        model.playbackSnapshot = Self.playbackSnapshot(position: elapsed, rate: rate)
    }

    func mergeSnapshot(_ snapshot: NowPlayingSnapshot, generation: UInt64) {
        guard generation == contentGeneration else { return }
        current = snapshot
        duration = snapshot.duration
        rebuildContent()
        model.playbackSnapshot = Self.playbackSnapshot(position: snapshot.position, rate: snapshot.playbackRate)
    }

    func setArtwork(
        image: PlatformImage,
        fallback snapshot: NowPlayingSnapshot,
        generation: UInt64
    ) {
        guard generation == contentGeneration, let data = image.jpegData(compressionQuality: 0.9) else { return }
        if current == nil { current = snapshot }
        artworkData = data
        rebuildContent()
    }

    func setArtwork(data: Data, fallback snapshot: NowPlayingSnapshot, generation: UInt64) {
        guard generation == contentGeneration else { return }
        guard PlatformImage(data: data) != nil else {
            Logger.artworkCache.warning("NowPlayingCenterPresenter: downloaded artwork could not be decoded")
            return
        }
        if current == nil { current = snapshot }
        artworkData = data
        rebuildContent()
    }

    func updateLikeCommand(songAvailable: Bool, isFavorite: Bool) {
        canFavorite = songAvailable
        self.isFavorite = isFavorite
        rebuildCommands()
    }

    func updateCommandAvailability(isLiveStream: Bool) {
        self.isLiveStream = isLiveStream
        rebuildCommands()
    }

    // MARK: - Model

    nonisolated static func playbackSnapshot(position: TimeInterval, rate: Float) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            state: rate > 0 ? .playing(rate: rate) : .paused,
            elapsedTime: max(0, position),
            timestamp: Date()
        )
    }

    private func rebuildContent() {
        guard let snapshot = current else {
            model.content = nil
            return
        }
        let artwork = artworkData.map { data in
            // Unique to the song, so a new song's cover is always fetched afresh even when it is
            // the same album art as the last one's.
            Artwork(id: "\(snapshot.songId ?? snapshot.title)#\(snapshot.coverArtId ?? "")") { _ in
                try ArtworkRepresentation(data: data)
            }
        }
        if snapshot.isLiveStream {
            let station = snapshot.radioStationName ?? snapshot.title
            model.content = RadioContent(
                id: "radio:\(station)",
                stationName: station,
                programName: snapshot.radioStationName == nil ? nil : snapshot.title,
                artwork: artwork
            )
            return
        }
        var content = MusicContent(
            id: snapshot.songId ?? snapshot.title,
            songTitle: snapshot.title,
            artistName: snapshot.artist ?? "",
            albumName: snapshot.album ?? "",
            type: .audio,
            duration: duration > 0 ? .finite(duration) : nil,
            artwork: artwork
        )
        if let identifier = songEntityID(for: snapshot) {
            content.appEntityIdentifiers = [EntityIdentifier(for: SiriSongEntity.self, identifier: identifier)]
        }
        model.content = content
    }

    private func rebuildCommands() {
        let likeAction = likeAction
        model.commands = [
            .play { [weak playerService] in
                Logger.nowPlaying.info("[AUDIO-INTENT] play origin=remote-command")
                await playerService?.resume()
            },
            .pause { [weak playerService] in
                Logger.nowPlaying.info("[AUDIO-INTENT] pause origin=remote-command")
                await playerService?.pause()
            },
            .togglePlayPause { [weak playerService] in
                Logger.nowPlaying.info("[AUDIO-INTENT] toggle origin=remote-command")
                await playerService?.togglePlayPause()
            },
            .next { [weak playerService] in
                try await playerService?.skipToNext()
            }.enabled(!isLiveStream),
            .previous { [weak playerService] in
                try await playerService?.skipToPrevious()
            }.enabled(!isLiveStream),
            .seekToPosition { [weak playerService] position in
                await playerService?.seek(to: position)
            }.enabled(!isLiveStream),
            .feedback(title: String(localized: "Add to Favorites"), status: isFavorite ? .positive : .neutral) { _ in
                await likeAction?()
            }.enabled(canFavorite),
        ]
    }

    // MARK: - Siri context

    /// The Siri song entity for a server song; local files and radio have none.
    private func songEntityID(for snapshot: NowPlayingSnapshot) -> String? {
        guard !snapshot.isLiveStream, let songId = snapshot.songId, !songId.hasPrefix("local:"),
              let scope = entityScope() else { return nil }
        return MusicIntentID(scope: scope, kind: .song, resourceID: songId).rawValue
    }

    /// Tells Siri which song is playing, so requests about "this song" resolve to it.
    private func publishRelevantEntity(for snapshot: NowPlayingSnapshot) {
        guard let identifier = songEntityID(for: snapshot) else {
            clearRelevantEntities()
            return
        }
        let entity = SiriSongEntity(id: identifier, title: snapshot.title, artistName: snapshot.artist ?? "", albumTitle: snapshot.album)
        Task {
            do { try await RelevantEntities.shared.updateEntities([entity], for: .audio(.nowPlaying)) }
            catch { Logger.nowPlaying.debug("Could not publish the now-playing entity: \(error, privacy: .public)") }
        }
    }

    private func clearRelevantEntities() {
        Task { try? await RelevantEntities.shared.removeAllEntities(for: .audio(.nowPlaying)) }
    }
}
#endif

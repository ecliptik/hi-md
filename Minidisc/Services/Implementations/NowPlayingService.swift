import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

actor NowPlayingService: NowPlayingServiceProtocol {
    private weak var playerService: (any PlayerServiceProtocol)?
    private let artworkLoader = ArtworkLoader()
    private let artworkImageCache: ArtworkImageCache
    private let presenter: NowPlayingCenterPresenter
    private var commandsRegistered = false
    private var currentSong: NowPlayingSnapshot?
    private var contentGeneration: UInt64 = 0
    /// Fetches the current song's cover after its details are already showing.
    private var artworkTask: Task<Void, Never>?
    private var favoritesService: (any FavoritesServiceProtocol)?

    init(
        playerService: any PlayerServiceProtocol,
        artworkImageCache: ArtworkImageCache,
        presenter: NowPlayingCenterPresenter
    ) {
        self.playerService = playerService
        self.artworkImageCache = artworkImageCache
        self.presenter = presenter
    }

    func setFavoritesService(_ service: any FavoritesServiceProtocol) {
        favoritesService = service
    }

    // MARK: - Lifecycle

    func start() async {
        guard !commandsRegistered, let playerService else { return }
        commandsRegistered = true

        await presenter.start(playerService: playerService) { [weak self] in
            await self?.toggleFavoriteForCurrentTrack()
        }
    }

    func stop() async {
        cancelArtworkLoad()
        contentGeneration &+= 1
        let generation = contentGeneration
        currentSong = nil
        await presenter.clear(generation: generation)
        guard generation == contentGeneration else { return }
        await refreshLikeCommandState()
    }

    // MARK: - Update

    func update(with snapshot: NowPlayingSnapshot) async {
        if snapshot.isLiveStream {
            cancelArtworkLoad()
            contentGeneration &+= 1
            let generation = contentGeneration
            currentSong = nil
            // Omitting duration and elapsed time hides the live-stream scrubber.
            await presenter.setBaseInfo(for: snapshot, generation: generation)
            guard generation == contentGeneration else { return }
            await refreshLikeCommandState()

            if let coverArtId = snapshot.coverArtId,
               let cachedImage = await artworkImageCache.cached(for: coverArtId, tier: .hero) {
                guard generation == contentGeneration else { return }
                await presenter.setArtwork(
                    image: cachedImage,
                    fallback: snapshot,
                    generation: generation
                )
            }

            guard generation == contentGeneration else { return }
            await updateRemoteCommandsAvailability(isLiveStream: true)
            return
        }

        if let songId = snapshot.songId, currentSong?.songId == songId {
            let generation = contentGeneration
            await updateRemoteCommandsAvailability(isLiveStream: false)
            guard generation == contentGeneration, currentSong?.songId == songId else { return }
            // Merge position updates so already-loaded artwork survives.
            await presenter.mergeSnapshot(snapshot, generation: generation)
            return
        }

        cancelArtworkLoad()
        contentGeneration &+= 1
        let generation = contentGeneration

        currentSong = snapshot
        await presenter.setBaseInfo(for: snapshot, generation: generation)
        guard isCurrent(snapshot, generation: generation) else { return }
        await updateRemoteCommandsAvailability(isLiveStream: false)
        guard isCurrent(snapshot, generation: generation) else { return }
        await refreshLikeCommandState()
        guard isCurrent(snapshot, generation: generation) else { return }

        if let coverArtId = snapshot.coverArtId, await artworkImageCache.hasNoArtwork(coverArtId) {
            await showNoArtwork(fallback: snapshot, generation: generation)
            return
        }
        if let coverArtId = snapshot.coverArtId,
           let cachedImage = await artworkImageCache.cached(for: coverArtId, tier: .hero) {
            guard isCurrent(snapshot, generation: generation) else { return }
            await presenter.setArtwork(
                image: cachedImage,
                fallback: snapshot,
                generation: generation
            )
            return
        }

        // The disk cache or the server can take seconds, up to the 10 s request timeout offline.
        // Callers such as launch-time session restore and Siri must not wait for it, so the song's
        // details are published now and the cover follows when it arrives.
        guard snapshot.coverArtId != nil || snapshot.artworkURL != nil else { return }
        artworkTask = Task { [weak self] in
            await self?.loadArtwork(for: snapshot, generation: generation)
        }
    }

    /// Resolves the cover from the disk cache before asking the server. A newer song, a stop or a
    /// live stream moves the generation on, so a late result is dropped instead of shown.
    private func loadArtwork(for snapshot: NowPlayingSnapshot, generation: UInt64) async {
        if let coverArtId = snapshot.coverArtId {
            let image = await artworkImageCache.load(coverArtId: coverArtId, tier: .hero)
            guard isCurrent(snapshot, generation: generation) else { return }
            if let image {
                await presenter.setArtwork(image: image, fallback: snapshot, generation: generation)
                return
            }
            if await artworkImageCache.hasNoArtwork(coverArtId) {
                guard isCurrent(snapshot, generation: generation) else { return }
                await showNoArtwork(fallback: snapshot, generation: generation)
                return
            }
        }

        guard isCurrent(snapshot, generation: generation), let artworkURL = snapshot.artworkURL else { return }
        let result = await artworkLoader.artwork(for: artworkURL, headers: snapshot.artworkHeaders)
        guard isCurrent(snapshot, generation: generation) else { return }
        switch result {
        case .artwork(let data):
            await presenter.setArtwork(data: data, fallback: snapshot, generation: generation)
        case .noArtwork:
            await showNoArtwork(fallback: snapshot, generation: generation)
        case .unavailable:
            break
        }
    }

    private func isCurrent(_ snapshot: NowPlayingSnapshot, generation: UInt64) -> Bool {
        generation == contentGeneration && currentSong?.songId == snapshot.songId
    }

    private func cancelArtworkLoad() {
        artworkTask?.cancel()
        artworkTask = nil
    }

    /// The Minidisc cartridge on gold, in place of the server's stand-in image on the Lock Screen,
    /// in Control Center and in the Dynamic Island.
    private func showNoArtwork(fallback snapshot: NowPlayingSnapshot, generation: UInt64) async {
        guard let image = PlatformImage(named: "NowPlayingNoArtwork") else { return }
        await presenter.setArtwork(image: image, fallback: snapshot, generation: generation)
    }

    // MARK: - Periodic position push

    func pushPosition(
        elapsed: TimeInterval,
        rate: Float,
        duration: TimeInterval,
        songId: String
    ) async {
        guard elapsed >= 0, duration > 0, currentSong?.songId == songId else { return }
        let generation = contentGeneration
        await presenter.mergePosition(
            elapsed: elapsed,
            rate: rate,
            duration: duration,
            generation: generation
        )
    }

    // MARK: - Favourite

    private func toggleFavoriteForCurrentTrack() async {
        guard let favoritesService, let songId = currentSong?.songId, !songId.hasPrefix("local:") else { return }
        let generation = contentGeneration
        let wasFavorite = await favoritesService.isFavorite(itemType: .song, itemId: songId)
        guard generation == contentGeneration, currentSong?.songId == songId else { return }
        do {
            if wasFavorite {
                try await favoritesService.unstar(itemType: .song, itemId: songId)
            } else {
                try await favoritesService.star(itemType: .song, itemId: songId)
            }
            await refreshLikeCommandState()
            Logger.nowPlaying.info("[REMOTE] \(wasFavorite ? "unstarred" : "starred", privacy: .public) '\(songId, privacy: .public)' from a remote surface")
        } catch {
            Logger.nowPlaying.warning("[REMOTE] favourite toggle failed for '\(songId, privacy: .public)': \(error, privacy: .public)")
        }
    }

    private func refreshLikeCommandState() async {
        let generation = contentGeneration
        let songId = currentSong?.songId
        let canFavorite = songId != nil && songId?.hasPrefix("local:") != true
        let isFavorite: Bool
        if canFavorite, let songId, let favoritesService {
            isFavorite = await favoritesService.isFavorite(itemType: .song, itemId: songId)
        } else {
            isFavorite = false
        }
        guard generation == contentGeneration, songId == currentSong?.songId else { return }
        await presenter.updateLikeCommand(songAvailable: canFavorite, isFavorite: isFavorite)
    }

    // MARK: - Remote command availability

    private func updateRemoteCommandsAvailability(isLiveStream: Bool) async {
        await presenter.updateCommandAvailability(isLiveStream: isLiveStream)
        Logger.nowPlaying.debug(
            "[REMOTE] command availability updated — live=\(isLiveStream, privacy: .public) seek/next/previous=\(!isLiveStream, privacy: .public)"
        )
    }

}

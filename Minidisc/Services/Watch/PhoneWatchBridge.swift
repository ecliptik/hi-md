#if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
import Foundation
import Observation
import OSLog
import SwiftSonic
import UIKit
import WatchConnectivity

/// Publishes Now Playing to the watch app and carries out the commands it sends.
@MainActor
final class PhoneWatchBridge {
    private unowned let container: AppContainer
    private var delegate: Delegate?
    private var observation: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var lastSent: WatchNowPlaying?

    init(container: AppContainer) {
        self.container = container
    }

    func start() {
        guard WCSession.isSupported(), delegate == nil else { return }
        let delegate = Delegate(bridge: self)
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
        let playerState = container.playerState
        observation = Task { [weak self] in
            let changes = Observations {
                (playerState.currentTrack?.id, playerState.wantsPlayback, playerState.queue.count,
                 playerState.currentRadio?.name)
            }
            for await _ in changes { self?.setNeedsPublish() }
        }
        NotificationCenter.default.addObserver(forName: .minidiscFavoritesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setNeedsPublish() }
        }
    }

    func setNeedsPublish() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await self?.publish()
        }
    }

    private func publish() async {
        let session = WCSession.default
        // isWatchAppInstalled lags behind installs, so a missing app is left to updateApplicationContext's error.
        guard session.activationState == .activated, session.isPaired else { return }
        let state = await makeState()
        guard state != lastSent, let data = state.encoded else { return }
        do {
            try session.updateApplicationContext([WatchMessageKey.nowPlaying: data])
            lastSent = state
        } catch {
            Logger.player.debug("Watch context update failed: \(error, privacy: .public)")
        }
    }

    private func makeState() async -> WatchNowPlaying {
        let playerState = container.playerState
        var state = WatchNowPlaying()
        if let radio = playerState.currentRadio {
            state.title = radio.name
            state.artist = String(localized: "Live Radio")
        } else if let track = playerState.currentTrack {
            state.title = track.title
            state.artist = track.artist
            state.canFavorite = !track.isLocalFile
            state.isFavorite = container.favoritesService.isFavorite(itemType: .song, itemId: track.id)
            state.canSkip = playerState.queue.count > 1
            if let image = await container.artworkImageCache.load(coverArtId: track.coverArtId ?? track.id, tier: .thumb) {
                state.artwork = Self.thumbnail(image)
            }
        }
        state.isPlaying = playerState.wantsPlayback
        if let serverID = container.serverState.activeServer?.id.uuidString {
            for mood in Mood.allCases where await container.moodPlaylistService.playlistId(for: mood, serverId: serverID) != nil {
                state.moods.append(WatchMood(id: mood.rawValue, title: String(localized: mood.title), symbolName: mood.symbolName))
            }
        }
        return state
    }

    /// Small enough for the application context, which has a size limit.
    nonisolated static func thumbnail(_ image: UIImage, side: CGFloat = 120) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    fileprivate func perform(_ command: WatchCommand) async {
        let player = container.playerService
        switch command {
        case .togglePlayPause:
            await player.togglePlayPause()
        case .next:
            try? await player.skipToNext()
        case .previous:
            try? await player.skipToPrevious()
        case .toggleFavorite:
            guard let track = container.playerState.currentTrack, !track.isLocalFile else { return }
            let favorites = container.favoritesService
            if favorites.isFavorite(itemType: .song, itemId: track.id) {
                try? await favorites.unstar(itemType: .song, itemId: track.id)
            } else {
                try? await favorites.star(itemType: .song, itemId: track.id)
            }
        case .playMood(let id):
            guard let mood = Mood(rawValue: id) else { return }
            try? await MusicIntentService(container: container).play(mood: mood)
        }
        setNeedsPublish()
    }

    /// WatchConnectivity calls back on its own queue; commands hop to the main actor.
    private final class Delegate: NSObject, WCSessionDelegate, @unchecked Sendable {
        private weak var bridge: PhoneWatchBridge?

        init(bridge: PhoneWatchBridge) { self.bridge = bridge }

        nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
            Task { @MainActor [weak self] in self?.bridge?.setNeedsPublish() }
        }

        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            // A different watch was paired; start a session for it.
            WCSession.default.activate()
        }

        nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
            Task { @MainActor [weak self] in self?.bridge?.setNeedsPublish() }
        }

        nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
            guard let data = message[WatchMessageKey.command] as? Data, let command = WatchCommand.decode(data) else { return }
            Task { @MainActor [weak self] in await self?.bridge?.perform(command) }
        }
    }
}
#endif

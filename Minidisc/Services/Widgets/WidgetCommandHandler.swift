import Foundation
import OSLog

extension AppContainer {
    /// Performs what widgets, controls and the download Live Activity ask for.
    @MainActor
    func handleWidgetCommand(_ command: WidgetCommand) async throws {
        Logger.ui.info("[WIDGET] \(String(describing: command), privacy: .public)")
        switch command {
        case .setPlaying(let playing):
            if playing { await playerService.resume() } else { await playerService.pause() }
        case .togglePlayPause:
            await playerService.togglePlayPause()
        case .next:
            try await playerService.skipToNext()
        case .smartShuffle:
            try await playerService.playSmartShuffle()
        case .playMood(let raw):
            guard let mood = Mood(rawValue: raw) else { return }
            try await MusicIntentService(container: self).play(mood: mood)
        case .playCollection(let kind, let id):
            guard let server = serverState.activeServer,
                  let kind = MusicIntentKind(rawValue: kind) else { return }
            let scope = MusicIntentID.scope(baseURL: server.baseURL, username: server.username)
            try await MusicIntentService(container: self)
                .play(id: MusicIntentID(scope: scope, kind: kind, resourceID: id).rawValue)
        case .cancelDownload(let id):
            guard let serverId = serverState.activeServer?.id else { return }
            switch downloadActivities.kind(of: id) {
            case "album": try await downloadService.cancelDownloads(albumId: id, serverId: serverId)
            case "playlist": try await downloadService.cancelDownloads(playlistId: id, serverId: serverId)
            default: break
            }
        }
    }
}

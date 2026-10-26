import Foundation
import OSLog

/// "Minidisc. Minidisc. Minidisc. It really whips the llama's ass!", Minidisc's homage to Winamp's
/// demo.mp3. It's bundled with the app and imported through the local music library like any file
/// added with ADD > FILE, so it plays through the same player.
enum WinampDemo {
    static let resourceName = "MinidiscDemo"

    /// Adds the demo to the queue and moves it to the top, without starting playback. Returns
    /// whether it was queued; a failure (for example while a radio station plays) is retried the
    /// next time Winamp mode opens.
    @MainActor
    static func queueFirst(in container: AppContainer) async -> Bool {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            Logger.ui.error("Winamp: the demo clip is missing from the app bundle")
            return false
        }
        let song: DisplayableSong
        do {
            guard let imported = try await container.localMusic.importSongs([url], limit: 1).songs.first else { return false }
            song = imported
        } catch {
            Logger.ui.error("Winamp: couldn't add the demo clip: \(String(describing: error), privacy: .public)")
            return false
        }
        let player = container.playerService
        let state = container.playerState
        let countBefore = state.queue.count
        await player.appendToQueue([song])
        guard state.queue.count == countBefore + 1, state.queue.last?.id == song.id else { return false }
        // With a song already loaded, move the demo above it through the same selection-checked
        // move as a playlist drag, so the current song and gapless preparation stay intact.
        let last = state.queue.count - 1
        if last > 0, let selection = QueueTrackSelection(playerState: state, destinationIndex: last, destinationTrackID: song.id) {
            await player.moveQueueTrack(selection, toIndex: 0)
        }
        return true
    }
}

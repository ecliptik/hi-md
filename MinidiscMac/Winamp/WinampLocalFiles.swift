import AppKit
import OSLog
import UniformTypeIdentifiers

/// The playlist's ADD > FILE and ADD > DIR: audio files, or folders of them, chosen with the open
/// panel and added to the end of the queue. They go through the app's local music library, which
/// keeps a security-scoped bookmark to each, so the songs (`local:` IDs) still play after a
/// relaunch, through the same player as the iPhone's local files.
final class WinampLocalFiles {
    private let container: AppContainer
    private var task: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    var isBusy: Bool { task != nil }

    /// Asks for audio files, or for folders when `folders`, then queues what they hold.
    func add(folders: Bool) {
        guard task == nil else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.prompt = String(localized: "Add")
        if folders {
            panel.message = String(localized: "Choose folders to add. Every audio file in them and their subfolders goes on the playlist.")
        } else {
            panel.allowedContentTypes = [.audio]
            panel.message = String(localized: "Choose audio files to add to the playlist.")
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let library = container.localMusic
        let player = container.playerService
        let toasts = container.toastService
        let limit = MusicFolderBrowser.defaultSongLimit
        task = Task { [weak self] in
            defer { self?.task = nil }
            let imported: LocalMusicImport
            do {
                imported = try await library.importSongs(urls, limit: limit)
            } catch {
                guard !Task.isCancelled else { return }
                Logger.ui.error("Winamp: couldn't add local files: \(String(describing: error), privacy: .public)")
                self?.showProblem(String(localized: "Minidisc couldn't read the files or folders you chose."))
                return
            }
            guard !imported.songs.isEmpty else {
                self?.showProblem(String(localized: "There are no audio files there that Minidisc can play."))
                return
            }
            await player.appendToQueue(imported.songs)
            if imported.isTruncated {
                toasts.show(String(localized: "Only the first \(imported.songs.count) songs were added."), style: .info, duration: 6)
            }
        }
    }

    private func showProblem(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't Add Music")
        alert.informativeText = message
        alert.runModal()
    }
}

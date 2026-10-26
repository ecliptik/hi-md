import AppKit
import OSLog
import UniformTypeIdentifiers

/// Saving the play queue as an `.m3u8` file or a server playlist, and opening `.m3u` and `.m3u8`
/// files into it. Opened entries are resolved against the server through `M3UPlaylistResolver`,
/// with its caps on entries and concurrent lookups.
final class WinampPlaylistFiles {
    private let container: AppContainer
    private let source: WinampSubsonicSource
    private var task: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
        source = WinampSubsonicSource(serverService: container.serverService)
    }

    private static var playlistTypes: [UTType] {
        [UTType(filenameExtension: "m3u8"), UTType(filenameExtension: "m3u"), .m3uPlaylist].compactMap(\.self)
    }

    var isBusy: Bool { task != nil }

    // MARK: Save

    func save() {
        let songs = container.playerState.queue.filter { !$0.isLocalFile }
        guard !songs.isEmpty, task == nil else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .m3uPlaylist]
        panel.nameFieldStringValue = String(localized: "Playlist") + ".m3u8"
        panel.message = String(localized: "Songs are saved by artist, album and title, so Minidisc can find them on the server again.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = source
        task = Task { [weak self] in
            let paths = await M3UQueueExport.serverPaths(for: songs, lookup: source)
            let data = M3UPlaylist.encode(M3UQueueExport.entries(for: songs, paths: paths))
            do {
                try data.write(to: url, options: .atomic)
                self?.container.toastService.showSuccess(String(localized: "Playlist saved"))
            } catch {
                Logger.ui.error("Winamp: couldn't save the playlist: \(String(describing: error), privacy: .public)")
                NSAlert(error: error).runModal()
            }
            self?.task = nil
        }
    }

    // MARK: Open

    /// Opens a playlist file, replacing the queue or adding to it.
    func open(replacing: Bool) {
        guard task == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.playlistTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= M3UPlaylist.maximumFileSize, let data = try? Data(contentsOf: url) else {
            showProblem(String(localized: "This playlist file is too large or can't be read."))
            return
        }
        let entries = M3UPlaylist.decode(data)
        guard !entries.isEmpty else {
            showProblem(String(localized: "This file has no songs in it."))
            return
        }
        let resolver = M3UPlaylistResolver(lookup: source)
        let player = container.playerService
        let toasts = container.toastService
        task = Task { [weak self] in
            defer { self?.task = nil }
            let resolutions: [M3UResolution]
            do {
                resolutions = try await resolver.resolve(entries)
            } catch {
                guard !Task.isCancelled else { return }
                self?.showProblem(UserFacingError.from(error).displayMessage)
                return
            }
            let songs = resolutions.compactMap(\.song).map { DisplayableSong(from: $0) }
            let missing = resolutions.count - songs.count
            guard !songs.isEmpty else {
                self?.showProblem(String(localized: "None of the songs in this playlist were found on the server."))
                return
            }
            if replacing {
                _ = await toasts.perform { try await player.play(tracks: songs, startIndex: 0) }
            } else {
                await player.appendToQueue(songs)
            }
            if missing > 0 {
                toasts.show(String(localized: "Some songs weren't found"),
                            subtitle: String(localized: "\(missing) of \(resolutions.count) songs aren't on the server."),
                            style: .info, duration: 6)
            }
        }
    }

    // MARK: Server playlist

    /// Creates a playlist on the server with the queue's songs, after asking for a name.
    func saveToServer() {
        let songs = container.playerState.queue.filter { !$0.isLocalFile }
        guard !songs.isEmpty, task == nil else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save as Server Playlist")
        alert.informativeText = String(localized: "The playlist is created on your server with the songs in the queue.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Playlist Name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              PlaylistLibraryViewModel.isValidName(field.stringValue) else { return }
        let name = field.stringValue
        let library = PlaylistLibraryViewModel(playlistService: container.playlistService, toastService: container.toastService)
        // The library reports success or failure in a toast.
        task = Task { [weak self] in
            _ = await library.create(name: name, songs: songs)
            self?.task = nil
        }
    }

    private func showProblem(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't Open Playlist")
        alert.informativeText = message
        alert.runModal()
    }
}

import AppIntents
import OSLog
import SwiftUI

extension View {
    /// Keeps the library index, offline data, downloads and Siri parameters in step with the
    /// container while the app's window is open. The iOS and Mac apps attach it to their root view.
    func containerLifecycle(_ container: AppContainer?) -> some View {
        modifier(ContainerLifecycle(container: container))
    }
}

private struct ContainerLifecycle: ViewModifier {
    let container: AppContainer?
    @Environment(\.scenePhase) private var scenePhase

    private struct FavoritesSyncIdentity: Hashable { let serverID: UUID?; let online: Bool; let active: Bool }

    func body(content: Content) -> some View {
        content
            // Hearts read the local favorites store, so refresh it from the server's stars on
            // connecting and whenever the app comes forward: stars may change on other devices.
            .task(id: FavoritesSyncIdentity(serverID: container?.serverState.activeServer?.id,
                                            online: container?.serverState.isOnline == true,
                                            active: scenePhase == .active)) {
                guard let container, container.serverState.isOnline, scenePhase == .active else { return }
                try? await container.favoritesService.syncFromServer()
            }
            .task(id: container?.serverState.libraryIndexPreparationSnapshot) {
                guard let container else { return }
                let snapshot = container.serverState.libraryIndexPreparationSnapshot
                guard snapshot.isOnline else { return }
                await container.downloadService.restorePendingDownloads()
                await container.listenBrainzService.flushOfflineQueue()
                await container.libraryService.flushPendingScrobbles()
                do {
                    try await container.libraryCatalog.prepare(
                        automaticRefreshAllowed: snapshot.automaticRefreshAllowed
                    )
                    MinidiscShortcuts.updateAppShortcutParameters()
                } catch is CancellationError {
                } catch {
                    // The persistent cache remains usable; a later reconnect or manual
                    // refresh retries only the entity scans that never completed.
                    Logger.library.debug(
                        "Library index preparation deferred: \(error, privacy: .public)"
                    )
                }
            }
            .task(id: container?.offlineLibrary.request) {
                await container?.offlineLibrary.refresh()
            }
            .onChange(of: container?.serverState.isOfflineModeEnabled) { _, _ in
                guard let container else { return }
                let event = container.serverState.networkPathEvent
                Task { await container.playerService.handleNetworkPathChanged(event) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .minidiscOfflineLibraryChanged)) { _ in
                container?.offlineLibrary.revision += 1
            }
            .task(id: container?.offlineFavoritesSync.request) {
                await container?.offlineFavoritesSync.synchronize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .minidiscFavoritesChanged)) { _ in
                container?.offlineFavoritesSync.revision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistsChanged)) { _ in
                MinidiscShortcuts.updateAppShortcutParameters()
            }
            .onReceive(NotificationCenter.default.publisher(for: .minidiscMoodPlaylistsChanged)) { _ in
                MinidiscShortcuts.updateAppShortcutParameters()
            }
    }
}

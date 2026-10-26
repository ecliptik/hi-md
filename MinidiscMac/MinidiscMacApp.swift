import AppIntents
import OSLog
import SwiftData
import SwiftUI

/// The native Mac app. It builds the same AppContainer as the iOS app, so playback, the library
/// index, downloads and scrobbling are the shared services; only the windows are Mac-specific.
@main
struct MinidiscMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var interface = MacInterface()
    @AppStorage(MacInterface.showsMenuBarPlayerKey) private var showsMenuBarPlayer = true
    @Environment(\.scenePhase) private var scenePhase

    private nonisolated static let backgroundSyncCoordinator = BackgroundSyncCoordinator()

    init() {
        let intentRuntime = MinidiscRuntime.shared
        AppDependencyManager.shared.add(dependency: intentRuntime)
    }

    var body: some Scene {
        WindowGroup(id: MacMenuBarPlayer.mainWindowID) {
            MacLaunchContent(state: appDelegate.launcher.state, interface: interface, retryAction: appDelegate.launcher.retry)
                .containerLifecycle(activeContainer)
                .winampMode(activeContainer) // Winamp mode: MinidiscMac/Winamp
        }
        .commands { MacCommands(container: activeContainer, interface: interface) }
        .commands { WinampCommands() } // Winamp mode: View > Winamp Mode (⌘⇧W)
        .onChange(of: scenePhase) { _, newPhase in
            guard let container = activeContainer else { return }
            Task { await container.playerService.setAppVisible(newPhase != .background) }
            if newPhase != .active {
                Task { await container.playerService.saveCurrentPosition() }
            }
        }

        Settings {
            if let container = activeContainer {
                MacSettingsView()
                    .environment(\.appContainer, container)
            } else {
                ProgressView()
                    .padding()
            }
        }

        // MARK: Menu bar player

        MenuBarExtra("Minidisc", systemImage: "opticaldisc", isInserted: menuBarPlayerInserted) {
            if let container = activeContainer {
                MacMenuBarPlayer(container: container, interface: interface)
                    .environment(\.appContainer, container)
                    .environment(container.artworkImageCache)
            }
        }
        .menuBarExtraStyle(.window)
    }

    static func makeContainer(diagnostics: PlaybackDiagnostics, linkRouter: LinkRouter) async throws -> AppContainer {
        try await AppContainer.launch(diagnostics: diagnostics, linkRouter: linkRouter, backgroundSync: backgroundSyncCoordinator)
    }

    private var activeContainer: AppContainer? { appDelegate.launcher.container }

    /// Follows the setting, but ignores the system taking the item out of the menu bar: writing
    /// that back to the setting made SwiftUI re-insert the item and rebuild the menus in a loop.
    private var menuBarPlayerInserted: Binding<Bool> {
        Binding(get: { showsMenuBarPlayer }, set: { _ in })
    }
}

private struct MacLaunchContent: View {
    let state: MacLaunchState
    let interface: MacInterface
    let retryAction: () -> Void

    var body: some View {
        switch state {
        case .launching:
            ProgressView()
                .frame(minWidth: 720, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)

        case .ready(let container):
            MacRootView(container: container, interface: interface)
                .toastOverlay(reservesMiniPlayerSpace: false)
                .environment(\.appContainer, container)
                .environment(container.dominantColorExtractor)
                .environment(container.artworkImageCache)
                .modelContainer(container.modelContainer)
                .environment(container.toastService)

        case .failed:
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Minidisc couldn't open its local data. You can try again without restarting the app.")
            } actions: {
                Button("Retry", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
            .frame(minWidth: 720, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)
        }
    }
}

import AppIntents
import OSLog
import SwiftData
import SwiftUI

/// The native Mac app. It builds the same AppContainer as the iOS app, so playback, the library
/// index, downloads and scrobbling are the shared services; only the windows are Mac-specific.
@main
struct MinidiscMacApp: App {
    @State private var launchState: MacLaunchState = .launching
    @State private var launchAttempt = 1
    @State private var interface = MacInterface()
    @AppStorage(MacInterface.showsMenuBarPlayerKey) private var showsMenuBarPlayer = true
    @Environment(\.scenePhase) private var scenePhase
    private let runtime = MinidiscRuntime.shared

    private nonisolated static let backgroundSyncCoordinator = BackgroundSyncCoordinator()

    init() {
        let intentRuntime = MinidiscRuntime.shared
        AppDependencyManager.shared.add(dependency: intentRuntime)
    }

    var body: some Scene {
        WindowGroup(id: MacMenuBarPlayer.mainWindowID) {
            MacLaunchContent(state: launchState, interface: interface, retryAction: retryLaunch)
                .task(id: launchAttempt) {
                    await launchIfNeeded()
                }
                .containerLifecycle(activeContainer)
        }
        .commands { MacCommands(container: activeContainer, interface: interface) }
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

        MenuBarExtra(isInserted: $showsMenuBarPlayer) {
            if let container = activeContainer {
                MacMenuBarPlayer(container: container, interface: interface)
                    .environment(\.appContainer, container)
                    .environment(container.artworkImageCache)
            }
        } label: {
            Label("Minidisc", systemImage: activeContainer?.playerState.wantsPlayback == true ? "opticaldisc.fill" : "opticaldisc")
        }
        .menuBarExtraStyle(.window)
    }

    static func makeContainer(diagnostics: PlaybackDiagnostics) async throws -> AppContainer {
        try await AppContainer.launch(diagnostics: diagnostics, backgroundSync: backgroundSyncCoordinator)
    }

    private var activeContainer: AppContainer? {
        guard case .ready(let container) = launchState else { return nil }
        return container
    }

    private func retryLaunch() {
        guard case .failed = launchState else { return }
        launchState = .launching
        launchAttempt += 1
    }

    private func launchIfNeeded() async {
        guard case .launching = launchState else { return }
        runtime.diagnostics.record(.application(.launchStarted(attempt: launchAttempt)))
        do {
            let container = try await runtime.container()
            launchState = .ready(container)
            Task { await container.playerService.setAppVisible(true) }
            runtime.diagnostics.record(.application(.servicesReady))
            Logger.boot.info("Mac app services ready")
        } catch {
            let failure = error as NSError
            Logger.boot.fault(
                "AppContainer initialization failed: domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
            )
            runtime.diagnostics.record(
                .application(.launchFailed(errorDomain: failure.domain, errorCode: failure.code))
            )
            launchState = .failed
        }
    }
}

enum MacLaunchState {
    case launching
    case ready(AppContainer)
    case failed
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

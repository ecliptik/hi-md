import SwiftUI

struct RootView: View {
    @Environment(\.appContainer) private var container
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    @AppStorage("minidisc.localMusicEnabled") private var localMusicEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    /// Folders can change outside the app, so a configured library is rescanned now and then.
    private static let localMusicRescanInterval: Duration = .seconds(120)

    private struct LocalMusicPollingKey: Equatable {
        let scenePhase: ScenePhase
        let hasFolders: Bool
    }

    var body: some View {
        content
            // The accent chosen in Settings > Appearance; reading it here redraws on change.
            .tint(Color.minidiscAccent)
            // The text shade: the playing row's title is text, and the fill shade is under 4.5:1
            // on grouped and raised rows in dark mode.
            .environment(\.minidiscPlayingAccent, .minidiscTextAccent)
            // The server may have become reachable or unreachable while the app was away, or a
            // different server may now be active; neither always changes the network path.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { container?.networkMonitor.checkServerReachability() }
                // Pick up anything widgets and Spotlight show that changed while the app was open,
                // such as the recently played albums Home just loaded or a finished library sync.
                if phase == .background {
                    container?.widgetSnapshotPublisher.setNeedsPublish()
                    container?.spotlightIndexer?.setNeedsIndex()
                }
            }
            .onChange(of: container?.serverState.activeConnectionVersion) {
                container?.networkMonitor.checkServerReachability()
            }
            .task(id: LocalMusicPollingKey(scenePhase: scenePhase, hasFolders: container?.localMusic.snapshot.folders.isEmpty == false)) {
                guard scenePhase == .active, let library = container?.localMusic else { return }
                await library.refresh()
                // Without folders there is nothing to rescan; adding the first folder restarts this task.
                guard !library.snapshot.folders.isEmpty else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: Self.localMusicRescanInterval) } catch { break }
                    await library.refresh()
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let serverState = container?.serverState {
            if serverState.isLoadingPersistedState {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (serverState.activeServer != nil && onboardingComplete) || localMusicEnabled {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

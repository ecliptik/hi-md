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

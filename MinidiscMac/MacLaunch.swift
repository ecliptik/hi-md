import AppKit
import Observation
import OSLog

enum MacLaunchState {
    case launching
    case ready(AppContainer)
    case failed
}

/// Builds the shared services once the app has finished launching, whether or not a window is
/// open. Playback, the media keys and the menu bar player work without the main window, so its
/// absence must never hold them back.
@Observable
@MainActor
final class MacLauncher {
    private(set) var state: MacLaunchState = .launching
    private var attempt = 1
    private var isRunning = false
    private let runtime = MinidiscRuntime.shared

    var container: AppContainer? {
        guard case .ready(let container) = state else { return nil }
        return container
    }

    func launch() {
        guard case .launching = state, !isRunning else { return }
        isRunning = true
        Task {
            await run()
            isRunning = false
        }
    }

    func retry() {
        guard case .failed = state else { return }
        state = .launching
        attempt += 1
        launch()
    }

    private func run() async {
        runtime.diagnostics.record(.application(.launchStarted(attempt: attempt)))
        do {
            let container = try await runtime.container()
            state = .ready(container)
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
            state = .failed
        }
    }
}

/// Starts the services at launch and keeps AppKit from restoring stale windows.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let launcher = MacLauncher()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Saved window state can name a window the app no longer has, such as one from the old
        // Mac Catalyst build. AppKit then restores nothing and SwiftUI opens no window either,
        // so the app ignores saved state and always opens its main window. Window sizes are
        // kept separately and still come back.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launcher.launch()
    }
}

import SwiftUI
import SwiftData
import OSLog
import Foundation
import BackgroundTasks
import AppIntents

@main
struct MinidiscApp: App {
    @UIApplicationDelegateAdaptor(MinidiscAppDelegate.self) private var appDelegate
    @State private var launchState: AppLaunchState = .launching
    @State private var launchAttempt = 1
    @Environment(\.scenePhase) private var scenePhase
    private let runtime = MinidiscRuntime.shared
    private var playbackDiagnostics: PlaybackDiagnostics { runtime.diagnostics }

    private nonisolated static let backgroundSyncCoordinator = BackgroundSyncCoordinator()

    init() {
        let intentRuntime = MinidiscRuntime.shared
        AppDependencyManager.shared.add(dependency: intentRuntime)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "app.minidisc.wrapped.monthly-update",
            using: nil,
            launchHandler: Self.handleWrappedUpdateBackgroundTask
        )
    }

    /// `BGTaskScheduler` invokes a handler registered with `queue: nil` on a framework-owned queue.
    /// Keeping the handler outside the default-MainActor `App` context prevents Swift 6 from
    /// inserting a main-executor precondition at the callback entry point.
    private nonisolated static func handleWrappedUpdateBackgroundTask(_ task: BGTask) {
        guard let processingTask = task as? BGProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }
        let completion = BackgroundTaskCompletion(task: processingTask)
        let workTask = Task {
            let syncSucceeded = await backgroundSyncCoordinator.run(calendar: .current)
            let expired = Task.isCancelled
            _ = completion.complete(success: syncSucceeded && !expired) {
                if expired {
                    Logger.wrapped.warning("BGTask expired — rescheduling for tomorrow")
                }
                scheduleWrappedUpdate()
            }
        }
        processingTask.expirationHandler = {
            // The work task completes the BGTask after its waiter has been removed
            // from the coordinator. This preserves an in-flight cold-start waiter,
            // while still cancelling the physical run when this was the last waiter.
            workTask.cancel()
        }
    }

    nonisolated static func scheduleWrappedUpdate() {
        let request = BGProcessingTaskRequest(identifier: "app.minidisc.wrapped.monthly-update")
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date().addingTimeInterval(24 * 3600)
        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            if let error { Logger.wrapped.warning("Could not schedule the Wrapped update: \(error, privacy: .public)") }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchContent(state: launchState, retryAction: retryLaunch)
                // Widgets open minidisc:// links. On a cold launch the URL arrives while the
                // container is still being built and no tab view exists yet, so it is queued here
                // for MainTabView to open once it appears.
                .onOpenURL { url in runtime.linkRouter.open(url) }
                .task(id: launchAttempt) {
                    await launchIfNeeded()
                }
                .containerLifecycle(activeContainer)
        }
        .commands { PlaybackCommands(container: activeContainer) }
        .onChange(of: scenePhase) { _, newPhase in
            if let container = activeContainer {
                let isVisible = newPhase != .background
                Task { await container.playerService.setAppVisible(isVisible) }
            }
            if newPhase == .active {
                activeContainer?.offlineFavoritesSync.revision += 1
                activeContainer?.offlineLibrary.revision += 1
            }
            if newPhase == .inactive, let container = activeContainer {
                Task { await container.playerService.saveCurrentPosition() }
                Logger.session.info("App inactive — position flushed (iOS kill guard)")
            }
            guard newPhase == .background, let container = activeContainer else { return }
            guard container.playerState.currentRadio == nil,
                  container.playerState.currentTrack != nil else {
                Logger.session.info("App backgrounded during radio — preserving the last music session")
                return
            }
            let snapshot = SessionPayload(
                currentIndex: container.playerState.currentIndex,
                currentPosition: container.playerState.position,
                queue: container.playerState.queue,
                currentTrack: container.playerState.currentTrack,
                repeatMode: container.playerState.repeatMode,
                queueRevision: container.playerState.queueRevision
            )
            Task { await container.sessionService.save(playerState: snapshot) }
            Logger.session.info("App backgrounded — session flushed")
        }
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
        playbackDiagnostics.record(.application(.launchStarted(attempt: launchAttempt)))

        let newContainer: AppContainer
        do {
            newContainer = try await runtime.container()
        } catch {
            let failure = error as NSError
            Logger.boot.fault(
                "AppContainer initialization failed: domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
            )
            playbackDiagnostics.record(
                .application(.launchFailed(errorDomain: failure.domain, errorCode: failure.code))
            )
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            let report = playbackDiagnostics.makeReport(
                context: PlaybackDiagnostics.ReportContext(
                    appVersion: version,
                    appBuild: build,
                    operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                    playbackStatus: .idle,
                    isPlaybackAvailable: false,
                    networkPath: nil,
                    connectionVersion: nil
                )
            )
            launchState = .failed(diagnosticReport: report)
            return
        }

        launchState = .ready(newContainer)
        // A launch for CarPlay, Siri or background audio starts hidden.
        let isVisible = UIApplication.shared.applicationState != .background
        Task { await newContainer.playerService.setAppVisible(isVisible) }
        playbackDiagnostics.record(.application(.servicesReady))
        Logger.boot.info("App services ready")
    }

    static func makeContainer(diagnostics: PlaybackDiagnostics, linkRouter: LinkRouter) async throws -> AppContainer {
        let newContainer = try await AppContainer.launch(
            diagnostics: diagnostics,
            linkRouter: linkRouter,
            backgroundSync: MinidiscApp.backgroundSyncCoordinator
        )
        MinidiscApp.scheduleWrappedUpdate()
        return newContainer
    }
}

private enum AppLaunchState {
    case launching
    case ready(AppContainer)
    case failed(diagnosticReport: String)
}

private struct AppLaunchContent: View {
    let state: AppLaunchState
    let retryAction: () -> Void

    var body: some View {
        switch state {
        case .launching:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let container):
            RootView()
                // Toast content renders cover art, so these environments must wrap the overlay too.
                .toastOverlay()
                .environment(\.appContainer, container)
                .environment(container.dominantColorExtractor)
                .environment(container.artworkImageCache)
                .modelContainer(container.modelContainer)
                .environment(container.toastService)

        case .failed(let diagnosticReport):
            AppLaunchFailureView(
                diagnosticReport: diagnosticReport,
                retryAction: retryAction
            )
        }
    }
}

private struct AppLaunchFailureView: View {
    let diagnosticReport: String
    let retryAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Minidisc couldn't open its local data. You can try again without restarting the app.")
        } actions: {
            ShareLink(item: diagnosticReport) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .tint(.primary)

            Button("Retry", action: retryAction)
                .buttonStyle(.borderedProminent)
                .tint(MinidiscColors.accent)
        }
    }
}

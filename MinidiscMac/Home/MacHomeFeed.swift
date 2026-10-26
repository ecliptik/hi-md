import Foundation
import Observation

/// Home's feed for one server: the iPhone's HomeFeedViewModel, kept by the app so Home and its
/// See All pages share it and coming back to Home shows it straight away.
@Observable
@MainActor
final class MacHomeFeed {
    let container: AppContainer
    let serverID: UUID
    let feed: HomeFeedViewModel

    /// When the feed last loaded, and whether the server was reachable then.
    @ObservationIgnored private var lastLoad: (isOnline: Bool, date: Date)?

    /// Coming back to Home within this time shows the feed as it is.
    private static let freshness: TimeInterval = 5 * 60

    init(container: AppContainer, serverID: UUID) {
        self.container = container
        self.serverID = serverID
        feed = HomeFeedViewModel(libraryService: container.libraryService, cache: HomeFeedCache.shared,
                                 serverID: serverID, diagnostics: container.playbackDiagnostics)
    }

    var content: HomeFeedContent { HomeFeedContent(feed: feed, container: container) }

    var state: HomeFeedState {
        HomeFeedLayout.state(
            isOnline: container.serverState.isOnline,
            isLoading: feed.isLoading,
            isEmpty: feed.isEmpty,
            error: feed.error,
            hasPartialFailure: feed.hasPartialFailure,
            pending: feed.pendingSections,
            content: content
        )
    }

    /// Loads on first view, after going online or offline, and once the feed is a few minutes old.
    func loadIfNeeded() async {
        let isOnline = container.serverState.isOnline
        if let lastLoad, lastLoad.isOnline == isOnline, Date().timeIntervalSince(lastLoad.date) < Self.freshness,
           !feed.isEmpty {
            return
        }
        await load(preserveLayout: false)
    }

    /// Refresh, and after playlists or favourites change: the shelves change once, together.
    func reload() async {
        await load(preserveLayout: true)
    }

    private func load(preserveLayout: Bool) async {
        let isOnline = container.serverState.isOnline
        let started = Date()
        await feed.load(isOnline: isOnline, preserveLayout: preserveLayout)
        // A load cut short by leaving Home runs again next time.
        if !Task.isCancelled { lastLoad = (isOnline, started) }
    }
}

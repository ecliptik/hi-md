#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation
import OSLog

/// What DownloadService reports while it downloads an album or playlist.
protocol DownloadActivityReporting: AnyObject, Sendable {
    func started(collectionID: String, kind: String, title: String, coverArtId: String?, total: Int) async
    func progressed(collectionID: String, completed: Int, total: Int) async
    func finished(collectionID: String, completed: Int, total: Int) async
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// Shows album and playlist downloads as Live Activities on the Lock Screen and in the Dynamic Island.
@MainActor
final class DownloadActivityController: DownloadActivityReporting {
    private let artwork: WidgetArtworkWriter
    private var kinds: [String: String] = [:]

    init(artwork: WidgetArtworkWriter) {
        self.artwork = artwork
    }

    func started(collectionID: String, kind: String, title: String, coverArtId: String?, total: Int) async {
        kinds[collectionID] = kind
        guard total > 0, ActivityAuthorizationInfo().areActivitiesEnabled,
              !(await Self.exists(collectionID)) else { return }
        let attributes = DownloadActivityAttributes(
            collectionID: collectionID, kind: kind, title: title, artworkFile: await artwork.file(for: coverArtId)
        )
        let state = DownloadActivityAttributes.ContentState(completed: 0, total: total)
        do {
            _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        } catch {
            Logger.download.debug("Download Live Activity not started: \(error, privacy: .public)")
        }
    }

    func progressed(collectionID: String, completed: Int, total: Int) async {
        await Self.update(collectionID, state: DownloadActivityAttributes.ContentState(completed: completed, total: total))
    }

    func finished(collectionID: String, completed: Int, total: Int) async {
        kinds[collectionID] = nil
        let state = DownloadActivityAttributes.ContentState(completed: completed, total: total, isFinished: true)
        await Self.end(collectionID, state: state)
    }

    /// The kind of a collection with an active download, for the Live Activity's Cancel button.
    func kind(of collectionID: String) -> String? { kinds[collectionID] }

    // ActivityKit owns these objects and they are not Sendable, so each one is looked up and used
    // inside a single nonisolated function rather than kept in the controller's state.

    @concurrent
    private nonisolated static func exists(_ collectionID: String) async -> Bool {
        activity(for: collectionID) != nil
    }

    @concurrent
    private nonisolated static func update(_ collectionID: String, state: DownloadActivityAttributes.ContentState) async {
        guard let activity = activity(for: collectionID) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    @concurrent
    private nonisolated static func end(_ collectionID: String, state: DownloadActivityAttributes.ContentState) async {
        guard let activity = activity(for: collectionID) else { return }
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 120))
    }

    private nonisolated static func activity(for collectionID: String) -> Activity<DownloadActivityAttributes>? {
        Activity<DownloadActivityAttributes>.activities.first { $0.attributes.collectionID == collectionID }
    }
}
#else
/// The Mac has no Live Activities; this only remembers each download's kind for Cancel.
@MainActor
final class DownloadActivityController: DownloadActivityReporting {
    private var kinds: [String: String] = [:]

    init() {}

    func started(collectionID: String, kind: String, title: String, coverArtId: String?, total: Int) async {
        kinds[collectionID] = kind
    }

    func progressed(collectionID: String, completed: Int, total: Int) async {}

    func finished(collectionID: String, completed: Int, total: Int) async {
        kinds[collectionID] = nil
    }

    func kind(of collectionID: String) -> String? { kinds[collectionID] }
}
#endif

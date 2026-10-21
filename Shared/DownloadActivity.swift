// Live Activities are iOS-only; Mac Catalyst builds leave the download activity out.
#if !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents
import Foundation

/// A Live Activity for an album or playlist being downloaded.
nonisolated struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var completed: Int
        var total: Int
        var currentTitle: String?
        var isFinished = false

        var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    }

    var collectionID: String
    var kind: String
    var title: String
    var artworkFile: String?
}

/// The Live Activity's Cancel button.
struct CancelMinidiscDownloadIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Download"
    static let isDiscoverable = false
    @Parameter(title: "Identifier") var collectionID: String

    init() {}
    init(collectionID: String) { self.collectionID = collectionID }

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.cancelDownload(collectionID))
        return .result()
    }
}
#endif

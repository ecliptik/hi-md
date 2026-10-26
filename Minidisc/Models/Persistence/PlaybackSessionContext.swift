import Foundation
import SwiftData

/// The saved session's playing-from context (id = "current"), beside `PlaybackSession` in the
/// session store only. A model of its own rather than a new `PlaybackSession` attribute because
/// `PlaybackSession` is also part of the versioned main-store schema, which would need a new version.
@Model
final class PlaybackSessionContext {
    @Attribute(.unique) var id: String
    var contextData: Data

    init(contextData: Data) {
        self.id = "current"
        self.contextData = contextData
    }

    /// Nil when the data holds a context this build doesn't know, e.g. after a downgrade.
    func decodedContext() -> PlaybackContext? {
        try? JSONDecoder().decode(PlaybackContext.self, from: contextData)
    }
}

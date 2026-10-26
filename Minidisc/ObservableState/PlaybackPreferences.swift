import Foundation

/// What Autoplay does once an album the listener chose has played to the end.
nonisolated enum AutoplayAlbumDirection: String, CaseIterable, Identifiable, Sendable {
    /// Carry on with related music, as after any other queue.
    case similar
    /// Stop when the album ends; Autoplay still continues playlists and mixes.
    case stop

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .similar: "Keep Playing Similar Music"
        case .stop: "Stop After the Album"
        }
    }

    /// Whether Autoplay may extend a queue whose requested songs are `requested`.
    func allowsExtending(requested: [DisplayableSong]) -> Bool {
        self == .similar || !Self.isSingleAlbum(requested)
    }

    /// Two or more songs that all come from one album.
    static func isSingleAlbum(_ songs: [DisplayableSong]) -> Bool {
        guard songs.count > 1, let albumID = songs.first?.albumId else { return false }
        return songs.allSatisfy { $0.albumId == albumID }
    }
}

/// Keep UserDefaults access on MainActor and share initial preferences with PlayerState.
@MainActor
final class PlaybackPreferences {
    static let defaultVolume: Float = 0.7

    enum Key {
        static let lastVolume = "minidisc.lastVolume"
        static let autoExtendEnabled = "minidisc.player.autoExtendEnabled"
        static let autoplayAlbumDirection = "minidisc.player.autoplayAlbumDirection"
        static let autoplayCountsAsPlays = "minidisc.player.autoplayCountsAsPlays"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var restoredVolume: Float {
        guard defaults.object(forKey: Key.lastVolume) != nil else {
            return Self.defaultVolume
        }
        return Float(defaults.double(forKey: Key.lastVolume))
    }

    /// Muting must not replace the last audible volume used when playback resumes.
    func storeLastAudibleVolume(_ volume: Float) {
        guard volume > 0 else { return }
        defaults.set(volume, forKey: Key.lastVolume)
    }

    var isAutoExtendEnabled: Bool { defaults.bool(forKey: Key.autoExtendEnabled) }

    func setAutoExtendEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.autoExtendEnabled)
    }

    /// Written by the Autoplay settings page through `@AppStorage` with the same key.
    var autoplayAlbumDirection: AutoplayAlbumDirection {
        defaults.string(forKey: Key.autoplayAlbumDirection).flatMap(AutoplayAlbumDirection.init(rawValue:)) ?? .similar
    }

    /// Whether songs Autoplay added count as plays: scrobbles, ListenBrainz and Recently Played.
    var autoplayCountsAsPlays: Bool {
        defaults.object(forKey: Key.autoplayCountsAsPlays) == nil ? true : defaults.bool(forKey: Key.autoplayCountsAsPlays)
    }
}

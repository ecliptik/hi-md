import Foundation

/// Where the current queue came from, shown as "Playing from …" in the player.
///
/// Pure state beside the queue: the player keeps it while the queue is still that source's queue
/// (skips, appends, Instant Mix fill, auto-extend, reorder and removal) and clears it when a new,
/// unrelated queue replaces it. It is saved with the session, so it is Codable; a context that a
/// later build added and this one cannot decode restores as nil.
nonisolated enum PlaybackContext: Codable, Sendable, Hashable {
    /// An artist station from Discover's "Stations for You".
    case artistStation(artistId: String, artistName: String)
    /// "Rediscover Your Library".
    case smartShuffle
    /// An Instant Mix seeded by a song or an album.
    case instantMix(seed: InstantMixSeedKind, id: String, name: String)
    case album(id: String, name: String, coverArtId: String?)
    case playlist(id: String, name: String, coverArtId: String?)
    /// One of the Discover mood playlists.
    case mood(Mood, playlistId: String)
    /// A yearly Wrapped playlist.
    case wrapped(year: Int, playlistId: String)
    /// Live radio. The player derives this from `PlayerState.currentRadio` rather than storing it.
    case internetRadio(name: String)

    nonisolated enum InstantMixSeedKind: String, Codable, Sendable, Hashable {
        case song
        case album
    }

    /// Where tapping the label goes, when the source is something the app can open.
    nonisolated enum Destination: Sendable, Hashable {
        case artist(id: String, name: String)
        case album(id: String, name: String, coverArtId: String?)
        case playlist(id: String, name: String, coverArtId: String?)
    }

    /// The playlist context, recognising the mood and Wrapped playlists Minidisc creates by name.
    static func forPlaylist(id: String, name: String, coverArtId: String?) -> PlaybackContext {
        if let mood = Mood.forPlaylistName(name) {
            return .mood(mood, playlistId: id)
        }
        if let year = WrappedPlaylistService.wrappedYear(fromPlaylistName: name) {
            return .wrapped(year: year, playlistId: id)
        }
        return .playlist(id: id, name: name, coverArtId: coverArtId)
    }

    /// The source's name, e.g. "DJ Shadow Station".
    var title: String {
        switch self {
        case .artistStation(_, let artistName):
            String(localized: "\(artistName) Station", comment: "Playing-from label for an artist station; the argument is the artist.")
        case .smartShuffle:
            String(localized: "Smart Shuffle")
        case .instantMix(_, _, let name):
            String(localized: "\(name) Mix", comment: "Playing-from label for an Instant Mix; the argument is the song or album it started from.")
        case .album(_, let name, _), .playlist(_, let name, _), .internetRadio(let name):
            name
        case .mood(let mood, _):
            String(localized: mood.title)
        case .wrapped(let year, _):
            String(localized: "Your \(year) Wrapped")
        }
    }

    var symbolName: String {
        switch self {
        case .artistStation, .instantMix: "dot.radiowaves.left.and.right"
        case .smartShuffle: "sparkles"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .mood(let mood, _): mood.symbolName
        case .wrapped: "waveform"
        case .internetRadio: "antenna.radiowaves.left.and.right"
        }
    }

    var destination: Destination? {
        switch self {
        case .artistStation(let id, let name):
            .artist(id: id, name: name)
        case .instantMix(.album, let id, let name):
            .album(id: id, name: name, coverArtId: nil)
        case .album(let id, let name, let coverArtId):
            .album(id: id, name: name, coverArtId: coverArtId)
        case .playlist(let id, let name, let coverArtId):
            .playlist(id: id, name: name, coverArtId: coverArtId)
        case .mood(let mood, let playlistId):
            .playlist(id: playlistId, name: String(localized: mood.title), coverArtId: nil)
        case .wrapped(let year, let playlistId):
            .playlist(id: playlistId, name: WrappedPlaylistService.playlistName(year: year), coverArtId: nil)
        case .instantMix(.song, _, _), .smartShuffle, .internetRadio:
            nil
        }
    }

    /// VoiceOver label for the player's line, e.g. "Playing from DJ Shadow Station".
    var accessibilityLabel: String {
        String(localized: "Playing from \(title)", comment: "VoiceOver label for the player's playing-from line.")
    }

    /// The queue header, e.g. "Playing Next from DJ Shadow Station".
    var queueHeader: String {
        String(localized: "Playing Next from \(title)", comment: "Queue header naming where the queue came from.")
    }
}

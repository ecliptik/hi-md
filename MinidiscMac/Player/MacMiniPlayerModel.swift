import Observation
import OSLog
import SwiftSonic
import SwiftUI

/// What the MiniPlayer shows about the playing song beyond PlayerState: the format actually
/// playing, the play count and year from the server, the waveform once a local copy exists, and
/// the related songs. Everything is read-only; nothing here changes the server or playback.
@Observable
@MainActor
final class MacMiniPlayerModel {
    enum RelatedState: Equatable {
        case idle, loading, loaded, unavailable
    }

    private(set) var songID: String?
    private(set) var formatLabel: String?
    private(set) var playCount: Int?
    private(set) var year: Int?
    private(set) var waveform: WaveformEnvelope?
    private(set) var related: [DisplayableSong] = []
    private(set) var relatedState: RelatedState = .idle
    private(set) var canLoadMoreRelated = false
    @ObservationIgnored private var relatedCount = RelatedSongs.pageSize
    @ObservationIgnored private var relatedSongID: String?

    /// Shared by every MiniPlayer window, so a song is measured once.
    static let waveforms = WaveformStore.inCaches()
    /// A song streaming now is in the cache once it has fully loaded; check for it this often.
    private static let localCopyPollInterval: Duration = .seconds(15)

    /// Loads the details of `track`. Run from a task keyed by the song, so a skip cancels it.
    func load(_ track: DisplayableSong?, container: AppContainer) async {
        guard let track, !track.isLocalFile else {
            reset(to: track?.id)
            formatLabel = track.flatMap { NowPlayingFormat.codecName($0.audioFormat, bitRate: $0.bitRate) }
            return
        }
        if songID != track.id { reset(to: track.id) }
        formatLabel = NowPlayingFormat.label(originalSuffix: track.audioFormat, originalBitRate: track.bitRate,
                                             localFileExtension: nil, streamRequest: streamRequest(for: track, container))
        async let details: Void = loadDetails(track, container: container)
        async let local: Void = loadLocalCopy(track, container: container)
        _ = await (details, local)
    }

    private func reset(to id: String?) {
        songID = id
        formatLabel = nil
        playCount = nil
        year = nil
        waveform = nil
        if relatedSongID != id {
            related = []
            relatedState = .idle
            canLoadMoreRelated = false
            relatedCount = RelatedSongs.pageSize
            relatedSongID = nil
        }
    }

    private func streamRequest(for track: DisplayableSong, _ container: AppContainer) -> StreamRequest {
        let traits = StreamSourceTraits(suffix: track.audioFormat, bitRate: track.bitRate, channelCount: track.channelCount)
        return container.streamSettings.currentPolicy.request(for: traits)
    }

    /// The play count and year, which only the server's song record has.
    private func loadDetails(_ track: DisplayableSong, container: AppContainer) async {
        guard container.serverState.isOnline else { return }
        do {
            let connection = try await container.serverService.activeConnection()
            let song = try await connection.makeSwiftSonicClient(requestTimeout: 10, retryPolicy: .none).getSong(id: track.id)
            guard !Task.isCancelled, songID == track.id else { return }
            playCount = song.playCount
            year = song.year
        } catch {
            // The details are extras; the MiniPlayer simply leaves them out.
        }
    }

    /// The format and waveform from a downloaded or cached copy. A song that is streaming gets
    /// both once the stream cache has the whole file.
    private func loadLocalCopy(_ track: DisplayableSong, container: AppContainer) async {
        guard let serverID = container.serverState.activeServer?.id else { return }
        let key = "\(serverID.uuidString)-\(track.id)"
        if let cached = await Self.waveforms.cached(forKey: key), songID == track.id {
            waveform = cached
        }
        while !Task.isCancelled {
            if let url = await localURL(track, serverID: serverID, container: container) {
                guard songID == track.id else { return }
                formatLabel = NowPlayingFormat.label(originalSuffix: track.audioFormat, originalBitRate: track.bitRate,
                                                     localFileExtension: url.pathExtension, streamRequest: nil)
                if waveform == nil {
                    let envelope = await Self.waveforms.envelope(forKey: key, audioFile: url)
                    guard !Task.isCancelled, songID == track.id else { return }
                    waveform = envelope
                }
                return
            }
            try? await Task.sleep(for: Self.localCopyPollInterval)
        }
    }

    private func localURL(_ track: DisplayableSong, serverID: UUID, container: AppContainer) async -> URL? {
        switch await container.mediaResolver.localSource(songId: track.id, serverId: serverID) {
        case .downloaded(let url), .cached(let url): url
        default: nil
        }
    }

    // MARK: Related songs

    /// The server's similar songs for `track`; `more` asks for another page.
    func loadRelated(for track: DisplayableSong?, container: AppContainer, more: Bool = false) async {
        guard let track, !track.isLocalFile else {
            related = []
            relatedState = .unavailable
            return
        }
        if relatedSongID == track.id, !more, relatedState == .loaded || relatedState == .loading { return }
        if relatedSongID != track.id {
            relatedSongID = track.id
            related = []
            relatedCount = RelatedSongs.pageSize
        } else if more {
            relatedCount = min(relatedCount + RelatedSongs.pageSize, RelatedSongs.maximumCount)
        }
        guard container.serverState.isOnline else {
            relatedState = related.isEmpty ? .unavailable : .loaded
            return
        }
        relatedState = related.isEmpty ? .loading : relatedState
        let count = relatedCount
        do {
            let connection = try await container.serverService.activeConnection()
            let songs = try await connection.makeSwiftSonicClient().getSimilarSongs(id: track.id, count: count)
            guard !Task.isCancelled, relatedSongID == track.id else { return }
            related = RelatedSongs.filtered(songs.map { DisplayableSong(from: $0) }, excluding: track.id)
            relatedState = related.isEmpty ? .unavailable : .loaded
            canLoadMoreRelated = songs.count >= count && count < RelatedSongs.maximumCount
        } catch {
            guard !UserFacingError.isCancellation(error), relatedSongID == track.id else { return }
            Logger.library.debug("MiniPlayer related songs failed: \(error.localizedDescription, privacy: .public)")
            relatedState = related.isEmpty ? .unavailable : .loaded
        }
    }
}

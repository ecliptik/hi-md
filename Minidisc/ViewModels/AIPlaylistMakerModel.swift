import Foundation
import Observation
import OSLog
import SwiftSonic

/// Make a Playlist: the listener describes a playlist or picks a suggested idea, the AI chosen in
/// Settings > AI Recommendations makes it from the library, and it's saved to the server. Shared
/// by the iPhone and Mac screens.
/// What a cloud provider is told, shown once before anything is sent to it.
nonisolated enum AIPlaylistSharingNotice {
    static func text(for provider: AIRecommendationProvider) -> String {
        String(localized: "To make playlists, Hi-MD sends \(provider.title) your request, the names of your library's genres and up to 400 of its artists, and the title, artist, year and genre of up to 250 songs that might fit. Once you continue, the weekly mood playlists are chosen the same way. Nothing else is sent: no server address, account details or play counts. The terms of your API key apply.")
    }
}

@Observable
@MainActor
final class AIPlaylistMakerModel {
    enum Phase: Equatable {
        case idle
        case making
        case ready
        case saving
        case saved(playlistID: String)
        case failed(message: String, fixInSettings: Bool)
    }

    var request = ""
    private(set) var ideas: [AIPlaylistIdea] = []
    private(set) var isLoadingIdeas = false
    private(set) var phase: Phase = .idle
    /// The made playlist, which the listener can rename and trim before saving.
    var title = ""
    private(set) var summary = ""
    private(set) var songs: [Song] = []

    @ObservationIgnored let container: AppContainer
    @ObservationIgnored private var makeTask: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    var settings: AIRecommendationSettings { container.aiRecommendationSettings }
    var provider: AIRecommendationProvider { settings.provider }
    /// A cloud provider needs the listener's agreement before song names are sent to it.
    var needsSharingNotice: Bool { settings.needsPlaylistSharingNotice(for: provider) }
    var canMake: Bool {
        !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .making && phase != .saving
            && !needsSharingNotice
    }
    var displaySongs: [DisplayableSong] { songs.map { DisplayableSong(from: $0) } }
    /// A made playlist is showing, saved or not.
    var hasDraft: Bool {
        switch phase {
        case .ready, .saving, .saved: true
        case .idle, .making, .failed: false
        }
    }

    func acknowledgeSharing() {
        settings.acknowledgePlaylistSharing(for: provider)
    }

    func useAppleIntelligence() {
        settings.provider = .appleIntelligence
    }

    // MARK: - Ideas

    func loadIdeas() async {
        guard ideas.isEmpty, !isLoadingIdeas, !needsSharingNotice else { return }
        isLoadingIdeas = true
        defer { isLoadingIdeas = false }
        do {
            let model = try await AIPlaylistModels.current(settings)
            let profile = try await AIRecommender(container: container, settings: settings).listeningProfile()
            let genres = try await libraryGenres()
            let suggested = try await model.ideas(profile, genres: genres, count: 5)
            ideas = suggested.filter { !$0.title.isEmpty && !$0.prompt.isEmpty }
        } catch is CancellationError {
        } catch {
            // Ideas are a convenience; typing a request still works without them.
            Logger.ui.info("AI playlist ideas failed: \(error, privacy: .public)")
        }
    }

    func use(_ idea: AIPlaylistIdea) {
        request = idea.prompt
        make()
    }

    // MARK: - Making and saving

    func make() {
        guard canMake else { return }
        makeTask?.cancel()
        phase = .making
        let request = request
        makeTask = Task {
            do {
                let model = try await AIPlaylistModels.current(settings)
                let library = try await librarySongs()
                let draft = try await AIPlaylistMaker(model: model, library: { library }).make(request)
                guard !Task.isCancelled else { return }
                title = draft.title
                summary = draft.summary
                songs = draft.songs
                phase = .ready
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                phase = Self.failure(error)
            }
        }
    }

    func cancel() {
        makeTask?.cancel()
        makeTask = nil
        if phase == .making { phase = .idle }
    }

    func remove(at offsets: IndexSet) {
        songs = songs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    func remove(songID: String) {
        songs.removeAll { $0.id == songID }
    }

    /// Moves songs as a list drag does: `destination` is a position in the list before the move.
    func move(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { songs[$0] }
        var rest = songs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let index = destination - offsets.count { $0 < destination }
        rest.insert(contentsOf: moving, at: max(0, min(index, rest.count)))
        songs = rest
    }

    /// Saves to the server with the request as its description and a gradient cover, as the
    /// mood playlists have.
    func save() async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !songs.isEmpty, phase == .ready else { return }
        phase = .saving
        do {
            let description = summary.isEmpty ? request : "\(summary) (\(request))"
            let playlist = try await container.playlistService.createPlaylist(name: name, description: description)
            try await container.playlistService.addTracks(playlistId: playlist.id, songs: songs)
            let cover = PlaylistCoverManager(downloadService: container.downloadService, artworkImageCache: container.artworkImageCache)
            _ = await cover.applyGradientCover(.neutral(shape: Self.coverShapes.randomElement() ?? .prism),
                                               playlistId: playlist.id, title: name, coverArtId: nil)
            phase = .saved(playlistID: playlist.id)
            container.toastService.showSuccess(String(localized: "Saved \(name) to Playlists"))
        } catch {
            Logger.playlist.error("Saving an AI playlist failed: \(error, privacy: .public)")
            phase = .ready
            container.toastService.showError(String(localized: "Couldn't save the playlist. Try again."))
        }
    }

    /// Starts over for another playlist, keeping the ideas.
    func reset() {
        cancel()
        request = ""
        title = ""
        summary = ""
        songs = []
        phase = .idle
    }

    // MARK: - Library

    private func librarySongs() async throws -> [Song] {
        guard let serverID = container.serverState.activeServer?.id else { throw MusicIntentError.noServer }
        return try await LibraryFacets.allSongs(store: container.libraryIndexStore, serverID: serverID)
    }

    private func libraryGenres() async throws -> [String] {
        guard let serverID = container.serverState.activeServer?.id else { return [] }
        return try await LibraryFacets.load(.genre, store: container.libraryIndexStore, serverID: serverID)
            .sorted { $0.songCount > $1.songCount }.map(\.name)
    }

    private static let coverShapes: [PlaylistGradientShape] = [.aurora, .prism, .lagoon, .sunset, .bloom, .ember]

    private static func failure(_ error: any Error) -> Phase {
        if let error = error as? AIRecommendationError {
            return .failed(message: String(localized: error.localizedStringResource), fixInSettings: error.isFixedInSettings)
        }
        if let error = error as? AIPlaylistError {
            return .failed(message: String(localized: error.localizedStringResource), fixInSettings: false)
        }
        return .failed(message: String(localized: "Hi-MD couldn't make that playlist. Try again."), fixInSettings: false)
    }
}

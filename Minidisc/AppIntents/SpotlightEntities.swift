#if compiler(>=6.4) && canImport(MediaIntents)
import AppIntents
import Foundation

// Artists, albums and playlists from the active server appear in Spotlight and in Apple
// Intelligence's semantic search. SpotlightIndexer keeps the index current; songs stay out of
// it to keep large libraries cheap to index, and remain reachable through Siri and in-app search.

@available(iOS 27.0, *)
extension SiriArtistEntity: IndexedEntity {}

@available(iOS 27.0, *)
extension SiriAlbumEntity: IndexedEntity {}

@available(iOS 27.0, *)
extension SiriPlaylistEntity: IndexedEntity {}

/// Opens a Spotlight result, or a Shortcuts "Open" action, on the item's screen.
@MainActor
private func open(_ id: String, name: String, runtime: MinidiscRuntime) async throws {
    let container = try await runtime.container()
    guard let server = container.serverState.activeServer else { throw MusicIntentError.noServer }
    guard let reference = MusicIntentID(rawValue: id),
          reference.scope == MusicIntentID.scope(baseURL: server.baseURL, username: server.username) else {
        throw MusicIntentError.differentServer
    }
    container.linkRouter.open(reference, name: name)
}

@available(iOS 27.0, *)
struct OpenMinidiscAlbumIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Album"
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    @Parameter(title: "Album") var target: SiriAlbumEntity
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        try await open(target.id, name: target.title, runtime: runtime)
        return .result()
    }
}

@available(iOS 27.0, *)
struct OpenMinidiscArtistIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Artist"
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    @Parameter(title: "Artist") var target: SiriArtistEntity
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        try await open(target.id, name: target.name, runtime: runtime)
        return .result()
    }
}

@available(iOS 27.0, *)
struct OpenMinidiscPlaylistIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Playlist"
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    @Parameter(title: "Playlist") var target: SiriPlaylistEntity
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        try await open(target.id, name: target.title, runtime: runtime)
        return .result()
    }
}
#endif

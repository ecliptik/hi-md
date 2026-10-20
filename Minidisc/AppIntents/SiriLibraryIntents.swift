#if compiler(>=6.4) && canImport(MediaIntents)
import AppIntents
import Foundation

// The iOS 27 audio actions beyond playback. Siri resolves "this song" to the now-playing entity
// that NowPlayingCenterPresenter publishes, so these work on the current song as well as on
// songs, albums and artists Siri finds through the entity queries.

@available(iOS 27.0, *)
@AppEnum(schema: .audio.affinityState)
enum SiriAffinity: String {
    case like
    case dislike
    case unset
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .like: "Love", .dislike: "Dislike", .unset: "No Rating"
    ]
}

/// "Add this song to my library": stars it on the server.
@available(iOS 27.0, *)
@AppIntent(schema: .audio.addToLibrary)
struct AddToLibrarySiriIntent: AppIntent {
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    var audioEntity: SiriMusicItem
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        runtime.diagnostics.record(.musicIntent(.libraryAction))
        try await MusicIntentService(container: try await runtime.container()).setFavorite(id: audioEntity.id, true)
        return .result()
    }
}

/// "Add this to my Road Trip playlist".
@available(iOS 27.0, *)
@AppIntent(schema: .audio.addToPlaylist)
struct AddToPlaylistSiriIntent: AppIntent {
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    var audioEntity: SiriMusicItem
    var playlist: SiriPlaylistEntity
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        runtime.diagnostics.record(.musicIntent(.libraryAction))
        try await MusicIntentService(container: try await runtime.container()).add(id: audioEntity.id, toPlaylist: playlist.id)
        return .result()
    }
}

/// "Start a station based on this song": an Instant Mix seeded by the playing song.
@available(iOS 27.0, *)
@AppIntent(schema: .audio.createStation)
struct CreateStationSiriIntent: AudioPlaybackIntent {
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        runtime.diagnostics.record(.musicIntent(.audioPlayback))
        try await MusicIntentService(container: try await runtime.container()).startStation(from: nil)
        return .result()
    }
}

/// "I love this song" stars it; "I don't like this song" and clearing the rating unstar it.
/// Subsonic has no dislike, so removing the star is the closest match.
@available(iOS 27.0, *)
@AppIntent(schema: .audio.updateAudioAffinity)
struct UpdateAffinitySiriIntent: AppIntent {
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    var target: SiriMusicItem
    var affinityState: SiriAffinity
    @Dependency private var runtime: MinidiscRuntime

    @MainActor
    func perform() async throws -> some IntentResult {
        runtime.diagnostics.record(.musicIntent(.libraryAction))
        try await MusicIntentService(container: try await runtime.container())
            .setFavorite(id: target.id, affinityState == .like)
        return .result()
    }
}
#endif

import Foundation
import FoundationModels
import OSLog
import SwiftSonic

nonisolated enum SmartSearchError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable, noServer, notUnderstood

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "Apple Intelligence isn't available on this iPhone right now."
        case .noServer: "Open Minidisc and connect to your music server first."
        case .notUnderstood: "Minidisc couldn't turn that into a search. Try naming a genre, decade, artist or mood."
        }
    }
}

nonisolated struct SmartSearchResult: Sendable {
    let query: LibraryQuery
    let songs: [DisplayableSong]
}

/// Natural-language search over the local library index. The on-device model only turns the
/// request into `LibraryQuery` filters; matching runs locally, so results are never invented
/// and it works offline.
@MainActor
struct SmartSearchService {
    private nonisolated static let pageSize = 2000

    let serverState: ServerState
    let store: LibraryIndexStore

    /// Whether to offer smart search at all: the model must be ready on this device.
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func search(_ text: String, now: Date = .now) async throws -> SmartSearchResult {
        guard let serverID = serverState.activeServer?.id else { throw SmartSearchError.noServer }
        let query = try await Self.interpret(text)
        guard !query.isEmpty else { throw SmartSearchError.notUnderstood }
        let songs = try await Self.matchingSongs(query, store: store, serverID: serverID, now: now)
        try Task.checkCancellation()
        return SmartSearchResult(query: query, songs: songs.map { DisplayableSong(from: $0) })
    }

    @concurrent
    nonisolated static func matchingSongs(_ query: LibraryQuery, store: LibraryIndexStore,
                                          serverID: UUID, now: Date) async throws -> [Song] {
        var matches: [Song] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await store.songs(serverID: serverID, offset: offset, count: pageSize)
            matches += page.filter { LibraryQueryFilter.matches($0, query, now: now) }
            guard page.count == pageSize else { break }
            offset += pageSize
        }
        return LibraryQueryFilter.rank(matches)
    }

    // MARK: - Model

    private nonisolated static let instructions = """
        You turn a person's request for music into search filters for their own music library.
        Fill in only what the request mentions or clearly implies. A decade such as "the 90s" \
        means 1990 to 1999. Words like mellow, relaxed or laid back mean the chill mood; calm \
        late-night music means night; upbeat means energetic; music to work out to means workout; \
        music to concentrate to means focus. Never invent artists or genres.
        """

    @concurrent
    nonisolated static func interpret(_ text: String) async throws -> LibraryQuery {
        guard SystemLanguageModel.default.isAvailable else { throw SmartSearchError.unavailable }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: text, generating: GeneratedLibraryQuery.self)
            return response.content.libraryQuery
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Guardrails, an unsupported language or output that doesn't fit the filters.
            Logger.ui.info("Smart search generation failed: \(error, privacy: .public)")
            throw SmartSearchError.notUnderstood
        }
    }
}

@Generable(description: "Filters for finding songs in a personal music library")
nonisolated struct GeneratedLibraryQuery {
    @Guide(description: "Music genres the request asks for, lowercase, such as rock, jazz or hip hop. Empty if none.")
    var genres: [String]
    @Guide(description: "Artist or band names named in the request. Empty if none.")
    var artists: [String]
    @Guide(description: "Earliest release year, such as 1990 for the 90s. 0 if the request gives no time period.")
    var fromYear: Int
    @Guide(description: "Latest release year, such as 1999 for the 90s. 0 if the request gives no time period.")
    var toYear: Int
    @Guide(description: "The feel the request describes, or none")
    var mood: GeneratedMood
    @Guide(description: "Whether the request is about how recently the songs were played")
    var recency: GeneratedRecency
    @Guide(description: "True only if the request asks for favourite, starred or loved songs")
    var favoritesOnly: Bool
    @Guide(description: "Words to find in song or album titles, only if the request quotes a title. Usually empty.")
    var titleWords: [String]

    var libraryQuery: LibraryQuery {
        var query = LibraryQuery()
        query.genres = genres.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        query.artists = artists.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let from = fromYear > 0 ? fromYear : nil
        let to = toYear > 0 ? toYear : nil
        if let lower = from ?? to, let upper = to ?? from {
            query.years = min(lower, upper)...max(lower, upper)
        }
        query.mood = mood.mood
        query.recency = recency.recency
        query.favoritesOnly = favoritesOnly
        query.titleWords = titleWords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return query
    }
}

@Generable
nonisolated enum GeneratedMood {
    case none, night, energetic, workout, chill, focus

    var mood: Mood? {
        switch self {
        case .none: nil
        case .night: .night
        case .energetic: .energetic
        case .workout: .workout
        case .chill: .chill
        case .focus: .focus
        }
    }
}

@Generable
nonisolated enum GeneratedRecency {
    case any, notPlayedLately, playedRecently

    var recency: LibraryQuery.Recency {
        switch self {
        case .any: .any
        case .notPlayedLately: .notPlayedLately
        case .playedRecently: .playedRecently
        }
    }
}

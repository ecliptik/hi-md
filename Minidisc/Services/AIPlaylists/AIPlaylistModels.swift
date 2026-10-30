import Foundation
import SwiftSonic

/// A playlist the model proposes from the listener's taste, made with one tap.
nonisolated struct AIPlaylistIdea: Sendable, Hashable, Identifiable, Codable {
    let title: String
    /// The request it stands for, as if the listener had typed it.
    let prompt: String

    var id: String { prompt }
}

/// What the model takes a request to mean, in the library's own genres and artists. A song
/// qualifies through any one of them; years, when given, limit all of them.
nonisolated struct AIPlaylistPlan: Sendable, Equatable {
    var genres: [String] = []
    var artists: [String] = []
    var years: ClosedRange<Int>?
    var mood: Mood?

    var isEmpty: Bool { genres.isEmpty && artists.isEmpty && years == nil && mood == nil }
}

/// The model's playlist: a name, a line about it, and the chosen candidates by number, in the
/// order to play them.
nonisolated struct AIPlaylistChoice: Sendable, Equatable {
    var title: String
    var summary: String
    var picks: [Int]
}

/// The library as the planner sees it: genre and artist names, most songs first.
nonisolated struct AIPlaylistLibrarySummary: Sendable, Equatable {
    var genres: [String]
    var artists: [String]
}

/// Plans, chooses and suggests playlists. Apple Intelligence and the cloud providers answer the
/// same three questions; everything else happens locally, so a playlist only ever holds songs
/// from the library.
nonisolated protocol AIPlaylistModel: Sendable {
    /// Whether planning sees the library's artists. Cloud models know which artists fit a
    /// request even when the tags don't say; the on-device model has no room for the list.
    var plansWithArtists: Bool { get }
    /// Candidates that fit in one request to choose from.
    var candidateLimit: Int { get }
    func plan(_ request: String, library: AIPlaylistLibrarySummary) async throws -> AIPlaylistPlan
    func choose(_ request: String, candidates: [String], count: Int) async throws -> AIPlaylistChoice
    func ideas(_ profile: AIListeningProfile, genres: [String], count: Int) async throws -> [AIPlaylistIdea]
}

nonisolated enum AIPlaylistError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case emptyRequest
    case noLibrary
    case notEnoughMatches

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyRequest: "Describe the playlist you'd like, or pick an idea."
        case .noLibrary: "Hi-MD hasn't finished reading your library yet. Try again in a few minutes."
        case .notEnoughMatches: "Not enough songs in your library fit that. Try describing it more broadly."
        }
    }
}

// MARK: - Prompts

nonisolated enum AIPlaylistPrompts {
    static let planSystem = """
        You help make playlists from a person's own music library. Given a request and the \
        library's genres (and sometimes its artists), choose the genres and artists from those \
        lists that fit the request. Use your knowledge of the artists' music, not just their \
        genre names: a request for chill music can include artists known for mellow records even \
        when their genre is pop or rock. Only use names exactly as listed. Give years only when the \
        request names a period, such as 1990 to 1999 for the 90s. Choose the mood that fits best, \
        or none.
        """

    static let chooseSystem = """
        You choose and order songs for a playlist from a numbered list of songs in a person's own \
        library. Pick songs that truly fit the request, using what you know about the songs and \
        artists; leave out ones that don't fit even if few remain. Avoid more than three songs by \
        one artist. Order them so the playlist flows. Then give it a short, plain title (no \
        quotation marks, no emoji, at most five words) and one sentence describing it.
        """

    static let ideasSystem = """
        You suggest playlists a person could make from their own music library, based on what \
        they listen to and the genres they have. Make each idea specific and different from the \
        others: a feeling, an occasion, an era or a sound, never just one artist. Give each a \
        short title (at most five words, no emoji) and the request that would make it, written \
        as the listener might type it.
        """

    static let moods = """
        Each mood means: night is calm, atmospheric late-night music; energetic is upbeat and \
        lively; workout is intense and driving; chill is relaxed and mellow; focus is calm, \
        steady, mostly instrumental background music.
        """

    static func planPrompt(_ request: String, library: AIPlaylistLibrarySummary) -> String {
        var lines = ["Request: \(request)", "", "Library genres: \(library.genres.joined(separator: "; "))"]
        if !library.artists.isEmpty {
            lines.append("Library artists: \(library.artists.joined(separator: "; "))")
        }
        lines.append("")
        lines.append(moods)
        return lines.joined(separator: "\n")
    }

    static func choosePrompt(_ request: String, candidates: [String], count: Int) -> String {
        """
        Request: \(request)

        Choose up to \(count) songs, by number:
        \(candidates.joined(separator: "\n"))
        """
    }

    static func ideasPrompt(_ profile: AIListeningProfile, genres: [String], count: Int) -> String {
        var lines: [String] = []
        if !profile.recentAlbums.isEmpty { lines.append("Recently played albums: \(profile.recentAlbums.joined(separator: "; "))") }
        if !profile.favoriteAlbums.isEmpty { lines.append("Favourite albums: \(profile.favoriteAlbums.joined(separator: "; "))") }
        if !profile.topArtists.isEmpty { lines.append("Most collected artists: \(profile.topArtists.joined(separator: "; "))") }
        lines.append("Library genres: \(genres.joined(separator: "; "))")
        lines.append("")
        lines.append("Suggest \(count) playlists.")
        return lines.joined(separator: "\n")
    }

    /// The JSON shapes the cloud models answer in; the on-device model uses guided generation.
    static let planJSON = """
        Answer with JSON only, in this shape:
        {"genres": ["…"], "artists": ["…"], "fromYear": 0, "toYear": 0, "mood": "none"}
        mood is one of none, night, energetic, workout, chill, focus; use 0 for no year.
        """
    static let chooseJSON = """
        Answer with JSON only, in this shape:
        {"title": "…", "summary": "…", "picks": [3, 1, 7]}
        """
    static let ideasJSON = """
        Answer with JSON only, in this shape:
        {"ideas": [{"title": "…", "prompt": "…"}]}
        """
}

// MARK: - Parsing cloud replies

nonisolated enum AIPlaylistParser {
    private struct Plan: Decodable {
        var genres: [String]?
        var artists: [String]?
        var fromYear: Int?
        var toYear: Int?
        var mood: String?
    }

    private struct Choice: Decodable {
        var title: String?
        var summary: String?
        var picks: [Int]
    }

    private struct Ideas: Decodable {
        struct Idea: Decodable { var title: String; var prompt: String }
        var ideas: [Idea]
    }

    static func plan(_ text: String) throws -> AIPlaylistPlan {
        let plan: Plan = try decode(text)
        return AIPlaylistPlan(
            genres: plan.genres ?? [], artists: plan.artists ?? [],
            years: years(from: plan.fromYear ?? 0, to: plan.toYear ?? 0),
            mood: plan.mood.flatMap { Mood(rawValue: $0.lowercased()) }
        )
    }

    static func choice(_ text: String) throws -> AIPlaylistChoice {
        let choice: Choice = try decode(text)
        return AIPlaylistChoice(title: choice.title ?? "", summary: choice.summary ?? "", picks: choice.picks)
    }

    static func ideas(_ text: String) throws -> [AIPlaylistIdea] {
        let ideas: Ideas = try decode(text)
        return ideas.ideas.map { AIPlaylistIdea(title: $0.title, prompt: $0.prompt) }
    }

    /// Either year alone stands for both; 0 means none.
    static func years(from: Int, to: Int) -> ClosedRange<Int>? {
        let lower = from > 0 ? from : nil
        let upper = to > 0 ? to : nil
        guard let low = lower ?? upper, let high = upper ?? lower else { return nil }
        return min(low, high)...max(low, high)
    }

    private static func decode<T: Decodable>(_ text: String) throws -> T {
        guard let object = AIRecommendationParser.span(of: text, from: "{", to: "}"),
              let value = try? JSONDecoder().decode(T.self, from: Data(object.utf8)) else {
            throw AIRecommendationError.badResponse
        }
        return value
    }
}

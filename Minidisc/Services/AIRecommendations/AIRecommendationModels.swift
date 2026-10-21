import Foundation

/// Where AI recommendations come from. Apple Intelligence runs on the device; the others are
/// cloud APIs that need the user's own key.
nonisolated enum AIRecommendationProvider: String, CaseIterable, Identifiable, Sendable {
    case appleIntelligence, anthropic, openAI

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .anthropic: "Anthropic (Claude)"
        case .openAI: "OpenAI"
        }
    }

    var needsAPIKey: Bool { self != .appleIntelligence }
    var keychainKey: String { "ai-recommendations.\(rawValue)" }
}

/// One suggested album, as the model returned it.
nonisolated struct AIRecommendation: Codable, Sendable, Hashable, Identifiable {
    var artist: String
    var album: String
    var year: Int?
    var reason: String

    var id: String { artist.lowercased() + "\u{1F}" + album.lowercased() }
}

/// Whether a recommendation is already in the library.
nonisolated enum AIRecommendationAvailability: Sendable, Hashable {
    case inLibrary(albumID: String, coverArtID: String?)
    /// The artist is in the library, but not this album.
    case artistInLibrary(artistID: String)
    case missing
}

nonisolated struct AIRecommendationResult: Sendable, Identifiable, Hashable {
    let recommendation: AIRecommendation
    let availability: AIRecommendationAvailability
    var id: String { recommendation.id }
}

/// What the model is told about the listener. Only names are sent, never IDs or server details.
nonisolated struct AIListeningProfile: Sendable, Equatable {
    var recentAlbums: [String] = []
    var topArtists: [String] = []
    var favoriteAlbums: [String] = []
    var playlists: [String] = []

    var isEmpty: Bool { recentAlbums.isEmpty && topArtists.isEmpty && favoriteAlbums.isEmpty }

    static let systemPrompt = """
        You are a music recommender. Suggest albums the listener doesn't own yet, based on their \
        listening. Prefer real, well-known albums whose artist and title you are certain of, mix \
        artists they own with new ones, and keep each reason to one short sentence that names \
        what in their listening it connects to. Never invent albums.
        """

    func prompt(count: Int) -> String {
        func list(_ title: String, _ items: [String]) -> String {
            items.isEmpty ? "" : "\(title):\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        return list("Recently played albums", recentAlbums)
            + list("Most collected artists", topArtists)
            + list("Favourite albums", favoriteAlbums)
            + list("Playlists", playlists)
            + """
            Recommend \(count) albums. Answer with JSON only, in this shape:
            {"recommendations": [{"artist": "…", "album": "…", "year": 1999, "reason": "…"}]}
            """
    }
}

nonisolated enum AIRecommendationError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case missingKey, unavailable, badResponse, http(Int), notEnoughListening

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missingKey: "Add an API key in Settings > Integrations > AI Recommendations."
        case .unavailable: "Apple Intelligence isn't available on this device right now."
        case .badResponse: "The recommendation service sent an answer Minidisc couldn't read. Try again."
        case .http(let status): "The recommendation service returned an error (\(status)). Check your key and try again."
        case .notEnoughListening: "Play some music first, so there's something to base recommendations on."
        }
    }
}

nonisolated enum AIRecommendationParser {
    private struct Envelope: Decodable { let recommendations: [AIRecommendation] }

    /// Reads `{"recommendations": [...]}` or a bare array, tolerating prose or code fences around it.
    static func parse(_ text: String) throws -> [AIRecommendation] {
        let decoder = JSONDecoder()
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
           let envelope = try? decoder.decode(Envelope.self, from: Data(text[start...end].utf8)) {
            return clean(envelope.recommendations)
        }
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"),
           let list = try? decoder.decode([AIRecommendation].self, from: Data(text[start...end].utf8)) {
            return clean(list)
        }
        throw AIRecommendationError.badResponse
    }

    private static func clean(_ items: [AIRecommendation]) -> [AIRecommendation] {
        var seen = Set<String>()
        return items.filter { !$0.artist.isEmpty && !$0.album.isEmpty && seen.insert($0.id).inserted }
    }
}

/// Library matching that ignores case, punctuation and "The".
nonisolated enum AIRecommendationMatcher {
    static func key(_ text: String) -> String {
        var value = text.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        if value.hasPrefix("the ") { value.removeFirst(4) }
        // Edition suffixes such as "(Deluxe Edition)" or "[Remastered]".
        if let bracket = value.firstIndex(where: { $0 == "(" || $0 == "[" }), bracket != value.startIndex {
            value = String(value[..<bracket])
        }
        return value.filter { $0.isLetter || $0.isNumber }
    }
}

/// Search links for albums that aren't in the library.
nonisolated enum AIRecommendationLinks {
    static func bandcamp(_ item: AIRecommendation) -> URL? {
        var components = URLComponents(string: "https://bandcamp.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(item.artist) \(item.album)")]
        return components?.url
    }

    static func musicBrainz(_ item: AIRecommendation) -> URL? {
        var components = URLComponents(string: "https://musicbrainz.org/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "release:\"\(item.album)\" AND artist:\"\(item.artist)\""),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "method", value: "advanced")
        ]
        return components?.url
    }
}

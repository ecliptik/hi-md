import Foundation

/// Where AI recommendations come from. Apple Intelligence runs on the device; the others are
/// cloud APIs that need the user's own key.
nonisolated enum AIRecommendationProvider: String, CaseIterable, Identifiable, Sendable {
    case appleIntelligence, anthropic, openAI

    var id: String { rawValue }

    /// The company, for the Settings picker and error messages. Brand names stay untranslated.
    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }

    /// The assistant people know, for the "Suggested by" pill and shared lists.
    var assistantName: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .anthropic: "Claude"
        case .openAI: "ChatGPT"
        }
    }

    /// Used when the model field is left empty. The user can type any model the provider offers.
    var defaultModel: String? {
        switch self {
        case .appleIntelligence: nil
        case .anthropic: "claude-opus-5-5"
        case .openAI: "gpt-5.6-terra"
        }
    }

    var needsAPIKey: Bool { self != .appleIntelligence }
    var keychainKey: String { "ai-recommendations.\(rawValue)" }
}

/// One suggested album. Once verified, the artist, title and year are MusicBrainz's, not the model's.
nonisolated struct AIRecommendation: Codable, Sendable, Hashable, Identifiable {
    var artist: String
    var album: String
    var year: Int?
    var reason: String
    /// The MusicBrainz release group, once verified.
    var releaseGroupID: String? = nil

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
        You are a music recommender. Suggest studio albums (not songs or singles) the listener \
        doesn't own yet, based on their listening. Prefer real, well-known albums whose artist and \
        title you are certain of, and mix artists they own with new ones. Keep each reason to one \
        short sentence about how the album sounds next to one of the listener's artists, naming \
        only that artist and the album's own artist and title. Never mention their playlists, \
        songs or other albums, and never invent albums.
        """

    /// For choosing from verified candidates: the model explains, it doesn't supply facts.
    static let choiceSystemPrompt = """
        You are a music recommender. You choose albums for a listener from a list of real albums \
        and say in one short sentence how each one sounds next to the listener's artist it is \
        similar to. Name only the album, its artist and that similar artist: never a playlist, a \
        song, another album, or any artist, year or genre that isn't on that album's line.
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

    /// The profile, then the candidates by id, each with the listener's artists it is similar to.
    func choicePrompt(_ candidates: [AIRecommendationCandidate], count: Int) -> String {
        func list(_ title: String, _ items: [String]) -> String {
            items.isEmpty ? "" : "\(title):\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        return list("Recently played albums", Array(recentAlbums.prefix(10)))
            + list("Most collected artists", Array(topArtists.prefix(15)))
            + list("Favourite albums", Array(favoriteAlbums.prefix(10)))
            + "Candidate albums (id: album — artist (year); similar to the listener's artists):\n"
            + candidates.map(\.promptLine).joined(separator: "\n")
            + """


            Choose up to \(count) albums from the candidates, best first; the listener's albums and \
            artists above are only to help you choose. Give each one's id exactly as listed and one \
            short sentence about the album's sound next to the artist after "similar to" on its line, \
            naming only that album, its artist and that artist. Don't mention playlists, songs or \
            the listener's albums. Answer with JSON only, in this shape:
            {"picks": [{"id": "c1", "reason": "…"}]}
            """
    }
}

nonisolated enum AIRecommendationError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case missingKey(AIRecommendationProvider)
    /// 401 or 403: the provider refused the key.
    case rejectedKey(AIRecommendationProvider)
    /// 404: the provider has no model by that name.
    case unknownModel(AIRecommendationProvider, String)
    /// 429: too many requests, or the account is out of credit.
    case rateLimited(AIRecommendationProvider)
    /// 408, 5xx or Anthropic's 529: the provider is down or overloaded.
    case serviceBusy(AIRecommendationProvider)
    case offline(AIRecommendationProvider)
    /// Any other status, with the provider's own message when it sent one.
    case http(AIRecommendationProvider, status: Int, message: String?)
    case unavailable, badResponse, notEnoughListening
    /// The model or the album checks took too long.
    case timedOut
    /// None of the suggestions could be confirmed with MusicBrainz.
    case unverified

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missingKey(let provider):
            "Add your \(provider.title) API key in Settings > Integrations > AI Recommendations."
        case .rejectedKey(let provider):
            "\(provider.title) didn't accept the API key. Check it in Settings > Integrations > AI Recommendations."
        case .unknownModel(let provider, let model):
            "\(provider.title) doesn't offer the model \(model). Check the model name in Settings > Integrations > AI Recommendations."
        case .rateLimited(let provider):
            "\(provider.title) is limiting requests, or your account is out of credit. Wait a minute and try again."
        case .serviceBusy(let provider):
            "\(provider.title) is busy right now. Try again in a few minutes."
        case .offline(let provider):
            "Couldn't reach \(provider.title). Check your connection and try again."
        case .http(let provider, let status, _):
            "\(provider.title) returned an error (\(status)). Check the model name in Settings > Integrations > AI Recommendations."
        case .unavailable: "Apple Intelligence isn't available on this device right now."
        case .badResponse: "The recommendation service sent an answer Hi-MD couldn't read. Try again."
        case .notEnoughListening: "Play some music first, so there's something to base recommendations on."
        case .timedOut: "Recommendations took too long. Try again."
        case .unverified: "Hi-MD couldn't confirm any of the suggested albums with MusicBrainz. Try again in a moment."
        }
    }

    /// Whether changing a setting fixes it, so the screen offers a way there.
    var isFixedInSettings: Bool {
        switch self {
        case .missingKey, .rejectedKey, .unknownModel, .http, .unavailable: true
        case .rateLimited, .serviceBusy, .offline, .badResponse, .notEnoughListening, .timedOut, .unverified: false
        }
    }

    /// The provider's own explanation, in English, shown under the message.
    var detail: String? {
        if case .http(_, _, let message) = self { message } else { nil }
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

    private struct PicksEnvelope: Decodable { let picks: [AIRecommendationPick] }

    /// Reads `{"picks": [{"id": …, "reason": …}]}` or a bare array, like `parse`.
    static func parsePicks(_ text: String) throws -> [AIRecommendationPick] {
        let decoder = JSONDecoder()
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
           let envelope = try? decoder.decode(PicksEnvelope.self, from: Data(text[start...end].utf8)) {
            return envelope.picks
        }
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"),
           let list = try? decoder.decode([AIRecommendationPick].self, from: Data(text[start...end].utf8)) {
            return list
        }
        throw AIRecommendationError.badResponse
    }

    private static func clean(_ items: [AIRecommendation]) -> [AIRecommendation] {
        var seen = Set<String>()
        return items.filter { !$0.artist.isEmpty && !$0.album.isEmpty && seen.insert($0.id).inserted }
    }
}

/// Library matching that ignores case, punctuation and "The", and reads "&" as "and".
nonisolated enum AIRecommendationMatcher {
    static func key(_ text: String) -> String {
        var value = text.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
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

    /// The release group's page once verified, a search otherwise.
    static func musicBrainz(_ item: AIRecommendation) -> URL? {
        if let id = item.releaseGroupID, !id.isEmpty, id.allSatisfy({ $0.isHexDigit || $0 == "-" }) {
            return URL(string: "https://musicbrainz.org/release-group/\(id)")
        }
        var components = URLComponents(string: "https://musicbrainz.org/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "release:\"\(item.album)\" AND artist:\"\(item.artist)\""),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "method", value: "advanced")
        ]
        return components?.url
    }
}

/// Plain text for the share sheet, laid out to paste cleanly into Notes or a message.
nonisolated enum AIRecommendationShareText {
    /// "Album — Artist (Year)", the reason, then the search links, one per line.
    static func single(_ item: AIRecommendation) -> String {
        lines(item).joined(separator: "\n")
    }

    /// A heading, then each album as a bullet with its details indented under it.
    static func all(_ items: [AIRecommendation], heading: String) -> String {
        let blocks = items.map { item in
            lines(item).enumerated().map { index, line in (index == 0 ? "• " : "  ") + line }.joined(separator: "\n")
        }
        return ([heading] + blocks).joined(separator: "\n\n")
    }

    private static func lines(_ item: AIRecommendation) -> [String] {
        var title = "\(item.album) — \(item.artist)"
        if let year = item.year { title += " (\(String(year)))" }
        var lines = [title]
        let reason = item.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { lines.append(reason) }
        if let url = AIRecommendationLinks.bandcamp(item) { lines.append("Bandcamp: \(url.absoluteString)") }
        if let url = AIRecommendationLinks.musicBrainz(item) { lines.append("MusicBrainz: \(url.absoluteString)") }
        return lines
    }
}

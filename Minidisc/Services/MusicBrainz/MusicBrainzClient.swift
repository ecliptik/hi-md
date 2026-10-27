import Foundation
import OSLog

/// One studio album (a MusicBrainz release group), with the facts the recommendations show.
nonisolated struct MusicBrainzAlbum: Sendable, Hashable, Codable {
    let releaseGroupID: String
    let title: String
    /// The artist credit as MusicBrainz prints it, joins included ("Simon & Garfunkel").
    let artistCredit: String
    let artistIDs: [String]
    let artistNames: [String]
    /// From the first release date.
    let year: Int?
    /// How many people rated it, a rough measure of how well known it is.
    let ratingVotes: Int
}

nonisolated enum MusicBrainzError: Error, Equatable {
    /// Offline, a timeout, or an error status.
    case unavailable
}

/// The MusicBrainz lookups AI recommendations rely on. A protocol so tests never touch the network.
nonisolated protocol MusicBrainzAlbumLookup: Sendable {
    /// Studio albums whose title matches `title`, by `artist` when one is given.
    func albums(titled title: String, by artist: String?) async throws -> [MusicBrainzAlbum]
    /// The artist's studio albums.
    func albums(byArtistMBID mbid: String) async throws -> [MusicBrainzAlbum]
}

/// Read-only MusicBrainz web service client for release groups. Every request waits for the
/// shared rate limiter (one a second, as MusicBrainz asks), sends a User-Agent naming the app,
/// and is remembered for the rest of the session, so a refresh only asks about new albums.
actor MusicBrainzClient: MusicBrainzAlbumLookup {
    static let shared = MusicBrainzClient()
    nonisolated static let userAgent = "Hi-MD/1.0 (https://github.com/ecliptik/hi-md)"
    nonisolated static let baseURL = URL(string: "https://musicbrainz.org/ws/2/release-group")!

    private let httpClient: any ArtistImageHTTPClient
    private let rateLimiter: MusicBrainzRateLimiter
    private var cache: [URL: [MusicBrainzAlbum]] = [:]

    init(httpClient: any ArtistImageHTTPClient = URLSession.shared, rateLimiter: MusicBrainzRateLimiter = .shared) {
        self.httpClient = httpClient
        self.rateLimiter = rateLimiter
    }

    func albums(titled title: String, by artist: String?) async throws -> [MusicBrainzAlbum] {
        try await fetch(Self.searchURL(title: title, artist: artist))
    }

    func albums(byArtistMBID mbid: String) async throws -> [MusicBrainzAlbum] {
        guard let url = Self.browseURL(artistMBID: mbid) else { return [] }
        return try await fetch(url)
    }

    // MARK: - Requests

    /// A release-group search limited to albums. Quotes and backslashes are escaped so a title
    /// can't change the query.
    nonisolated static func searchURL(title: String, artist: String?) -> URL {
        var query = "releasegroup:\"\(escape(title))\" AND primarytype:album"
        if let artist { query += " AND artist:\"\(escape(artist))\"" }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        return components.url!
    }

    /// The artist's albums with at least one official release, with credits and ratings.
    nonisolated static func browseURL(artistMBID: String) -> URL? {
        let mbid = artistMBID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mbid.isEmpty, mbid.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "artist", value: mbid),
            URLQueryItem(name: "type", value: "album"),
            URLQueryItem(name: "release-group-status", value: "website-default"),
            URLQueryItem(name: "inc", value: "artist-credits+ratings"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        return components.url
    }

    nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func fetch(_ url: URL) async throws -> [MusicBrainzAlbum] {
        if let cached = cache[url] { return cached }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        // One retry when MusicBrainz says it is over its limit (503).
        for attempt in 0..<2 {
            try await rateLimiter.waitForPermit()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await httpClient.data(for: request)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.ui.notice("MusicBrainz request failed: \(error, privacy: .public)")
                throw MusicBrainzError.unavailable
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 503, attempt == 0 { continue }
            guard (200..<300).contains(status) else {
                Logger.ui.notice("MusicBrainz returned \(status, privacy: .public)")
                throw MusicBrainzError.unavailable
            }
            let albums = try Self.parse(data)
            cache[url] = albums
            return albums
        }
        throw MusicBrainzError.unavailable
    }

    // MARK: - Responses

    private nonisolated struct Response: Decodable {
        let releaseGroups: [ReleaseGroup]
        private enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
    }

    private nonisolated struct ReleaseGroup: Decodable {
        struct Credit: Decodable {
            struct Artist: Decodable { let id: String; let name: String }
            let name: String
            let joinphrase: String?
            let artist: Artist
        }
        struct Release: Decodable { let status: String? }
        struct Rating: Decodable {
            let votesCount: Int?
            private enum CodingKeys: String, CodingKey { case votesCount = "votes-count" }
        }
        let id: String
        let title: String
        let primaryType: String?
        let secondaryTypes: [String]?
        let firstReleaseDate: String?
        let artistCredit: [Credit]?
        let releases: [Release]?
        let rating: Rating?

        private enum CodingKeys: String, CodingKey {
            case id, title, releases, rating
            case primaryType = "primary-type"
            case secondaryTypes = "secondary-types"
            case firstReleaseDate = "first-release-date"
            case artistCredit = "artist-credit"
        }
    }

    /// Keeps studio albums only: primary type Album, no secondary type (compilation, live,
    /// soundtrack, remix…), and an official release when the releases are listed.
    nonisolated static func parse(_ data: Data) throws -> [MusicBrainzAlbum] {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw MusicBrainzError.unavailable }
        return response.releaseGroups.compactMap { group in
            guard group.primaryType?.lowercased() == "album", group.secondaryTypes?.isEmpty ?? true else { return nil }
            if let releases = group.releases, !releases.isEmpty,
               !releases.contains(where: { $0.status?.lowercased() == "official" }) {
                return nil
            }
            let credits = group.artistCredit ?? []
            guard !credits.isEmpty else { return nil }
            let creditText = credits.map { $0.name + ($0.joinphrase ?? "") }.joined()
                .trimmingCharacters(in: .whitespaces)
            let year = group.firstReleaseDate.flatMap { Int($0.prefix(4)) }
            return MusicBrainzAlbum(
                releaseGroupID: group.id, title: group.title, artistCredit: creditText,
                artistIDs: credits.map(\.artist.id), artistNames: credits.map(\.artist.name),
                year: year, ratingVotes: group.rating?.votesCount ?? 0
            )
        }
    }
}

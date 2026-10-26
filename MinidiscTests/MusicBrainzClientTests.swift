import Foundation
import Testing
@testable import Minidisc

/// Canned MusicBrainz answers, in order. No real network.
private nonisolated final class StubHTTP: ArtistImageHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, Data)]
    private var requests: [URLRequest] = []

    init(_ responses: [(Int, Data)]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (status, data) = lock.withLock {
            requests.append(request)
            return responses.isEmpty ? (500, Data()) : responses.removeFirst()
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    var requestCount: Int { lock.withLock { requests.count } }
    var firstRequest: URLRequest? { lock.withLock { requests.first } }
}

private let releaseGroupsJSON = Data("""
{"release-groups": [
  {"id": "rg-1", "title": "The Soft Bulletin", "primary-type": "Album", "secondary-types": [],
   "first-release-date": "1999-05-17", "rating": {"value": 4.5, "votes-count": 12},
   "artist-credit": [{"name": "The Flaming Lips", "joinphrase": "", "artist": {"id": "a-lips", "name": "The Flaming Lips"}}],
   "releases": [{"id": "r1", "status": "Official"}]},
  {"id": "rg-2", "title": "Bookends", "primary-type": "Album",
   "first-release-date": "1968",
   "artist-credit": [{"name": "Simon", "joinphrase": " & ", "artist": {"id": "a-s", "name": "Paul Simon"}},
                     {"name": "Garfunkel", "artist": {"id": "a-g", "name": "Art Garfunkel"}}]},
  {"id": "rg-3", "title": "Greatest Hits", "primary-type": "Album", "secondary-types": ["Compilation"],
   "artist-credit": [{"name": "X", "artist": {"id": "a-x", "name": "X"}}]},
  {"id": "rg-4", "title": "Head Like a Hole", "primary-type": "Single",
   "artist-credit": [{"name": "Nine Inch Nails", "artist": {"id": "a-nin", "name": "Nine Inch Nails"}}]},
  {"id": "rg-5", "title": "Live Bootleg", "primary-type": "Album",
   "artist-credit": [{"name": "Y", "artist": {"id": "a-y", "name": "Y"}}],
   "releases": [{"id": "r5", "status": "Bootleg"}]}
]}
""".utf8)

@Suite("MusicBrainz client")
struct MusicBrainzClientTests {
    private func client(_ http: StubHTTP) -> MusicBrainzClient {
        MusicBrainzClient(httpClient: http, rateLimiter: MusicBrainzRateLimiter(minimumInterval: .zero))
    }

    @Test func keepsOnlyOfficialStudioAlbums() throws {
        let albums = try MusicBrainzClient.parse(releaseGroupsJSON)
        #expect(albums.map(\.releaseGroupID) == ["rg-1", "rg-2"])
        #expect(albums[0].year == 1999)
        #expect(albums[0].ratingVotes == 12)
        #expect(albums[1].artistCredit == "Simon & Garfunkel")
        #expect(albums[1].artistIDs == ["a-s", "a-g"])
    }

    @Test func searchSendsUserAgentAndRemembersAnswers() async throws {
        let http = StubHTTP([(200, releaseGroupsJSON)])
        let client = client(http)
        let first = try await client.albums(titled: "The Soft Bulletin", by: "The \"Flaming\" Lips")
        let second = try await client.albums(titled: "The Soft Bulletin", by: "The \"Flaming\" Lips")
        #expect(first == second)
        #expect(http.requestCount == 1)
        let request = try #require(http.firstRequest)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Minidisc/") == true)
        #expect(request.url?.host == "musicbrainz.org")
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "query" }?.value
        #expect(query == #"releasegroup:"The Soft Bulletin" AND primarytype:album AND artist:"The \"Flaming\" Lips""#)
    }

    @Test func retriesOnceWhenMusicBrainzIsBusy() async throws {
        let http = StubHTTP([(503, Data()), (200, releaseGroupsJSON)])
        #expect(try await client(http).albums(byArtistMBID: "0000-aaaa").count == 2)
        #expect(http.requestCount == 2)
    }

    @Test func errorsAreUnavailable() async {
        let client = client(StubHTTP([(500, Data())]))
        await #expect(throws: MusicBrainzError.unavailable) { try await client.albums(titled: "X", by: nil) }
    }

    @Test func browseRejectsMalformedIDs() {
        #expect(MusicBrainzClient.browseURL(artistMBID: "../../evil") == nil)
        #expect(MusicBrainzClient.browseURL(artistMBID: "b7ffd2af-418f-4be2-bdd1-22f8b48613da")?.query?.contains("type=album") == true)
    }
}

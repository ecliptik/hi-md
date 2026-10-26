import Foundation
import Testing
@testable import Minidisc

private nonisolated final class TopArtistsTransport: ListenBrainzTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let status: Int
    private let body: Data
    private var lastURL: URL?

    init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { lastURL = request.url }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    var url: URL? { lock.withLock { lastURL } }
}

private let topArtistsJSON = Data("""
{"payload": {"artists": [
  {"artist_name": "Pavement", "artist_mbid": "a-pavement", "listen_count": 40},
  {"artist_name": "Björk", "artist_mbids": ["a-bjork"], "listen_count": 30},
  {"artist_name": "Unknown"},
  {"listen_count": 3}
]}}
""".utf8)

@Suite("ListenBrainzClient — topArtists")
struct ListenBrainzClientTopArtistsTests {
    @Test func readsBothIDShapesAndSkipsBrokenEntries() async throws {
        let transport = TopArtistsTransport(status: 200, body: topArtistsJSON)
        let artists = try await ListenBrainzClient(transport: transport).topArtists(forUser: "listener")
        #expect(artists.map(\.name) == ["Pavement", "Björk", "Unknown"])
        #expect(artists.map(\.mbid) == ["a-pavement", "a-bjork", nil])
        #expect(transport.url?.path == "/1/stats/user/listener/artists")
    }

    @Test(arguments: [204, 404])
    func noStatisticsYetIsEmpty(status: Int) async throws {
        let artists = try await ListenBrainzClient(transport: TopArtistsTransport(status: status)).topArtists(forUser: "listener")
        #expect(artists.isEmpty)
    }

    @Test func invalidUsernameIsRejectedBeforeAnyRequest() async {
        let transport = TopArtistsTransport(status: 200, body: topArtistsJSON)
        await #expect(throws: ListenBrainzError.self) {
            try await ListenBrainzClient(transport: transport).topArtists(forUser: "../evil")
        }
        #expect(transport.url == nil)
    }
}

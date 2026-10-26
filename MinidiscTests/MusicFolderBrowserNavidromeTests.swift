import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

/// Answers folder endpoints with fixed bodies shaped like Navidrome 0.64's, and records each
/// request's query.
private final class NavidromeFixtureTransport: HTTPTransport, Sendable {
    let bodies: [String: String]
    private let queries = Mutex<[String: [[URLQueryItem]]]>([:])

    init(bodies: [String: String]) {
        self.bodies = bodies
    }

    func queries(_ endpoint: String) -> [[URLQueryItem]] { queries.withLock { $0[endpoint] ?? [] } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let endpoint = url.lastPathComponent.replacingOccurrences(of: ".view", with: "")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        queries.withLock { $0[endpoint, default: []].append(query) }
        let id = query.first { $0.name == "id" }?.value
        let body = bodies[id.map { "\(endpoint)?id=\($0)" } ?? endpoint] ?? bodies[endpoint]
            ?? NavidromeFixtures.failed(code: 70, message: "Not found")
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Response bodies in Navidrome's JSON shape: the OpenSubsonic envelope, numeric music folder
/// IDs, string artist, album and song IDs, nanosecond dates and the OpenSubsonic child fields.
private nonisolated enum NavidromeFixtures {
    static func ok(_ payload: String) -> String {
        """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome","serverVersion":"0.64.0 (5c4b1a2)","openSubsonic":true,\(payload)}}
        """
    }

    static func failed(code: Int, message: String) -> String {
        """
        {"subsonic-response":{"status":"failed","version":"1.16.1","type":"navidrome","serverVersion":"0.64.0 (5c4b1a2)","openSubsonic":true,"error":{"code":\(code),"message":"\(message)"}}}
        """
    }

    static let musicFolders = ok("""
        "musicFolders":{"musicFolder":[{"id":1,"name":"Music Library"},{"id":2,"name":"Audiobooks"}]}
        """)

    static let indexes = ok("""
        "indexes":{"index":[
          {"name":"A","artist":[{"id":"3a1bf0c2e4d1","name":"ABBA","coverArt":"ar-3a1bf0c2e4d1_0",
            "artistImageUrl":"https://music.example.com/share/img/ar-3a1bf0c2e4d1_0?size=600",
            "starred":"2024-03-01T10:20:30.123456789Z","userRating":4}]},
          {"name":"B","artist":[{"id":"7f2e9a0b11c3","name":"Björk","coverArt":"ar-7f2e9a0b11c3_0",
            "artistImageUrl":"https://music.example.com/share/img/ar-7f2e9a0b11c3_0?size=600"}]}],
          "lastModified":1730000000123,"ignoredArticles":"The El La Los Las Le Les Os As O A"}
        """)

    static let abba = ok("""
        "directory":{"child":[
          {"id":"al-arrival","parent":"3a1bf0c2e4d1","isDir":true,"title":"Arrival","name":"Arrival","album":"Arrival",
           "artist":"ABBA","year":1976,"genre":"Pop","coverArt":"al-al-arrival_0","playCount":12,
           "created":"2023-05-06T07:08:09.123456Z","artistId":"3a1bf0c2e4d1","songCount":2,"isVideo":false,
           "played":"2025-01-02T03:04:05.678Z","bpm":0,"comment":"","sortName":"arrival","mediaType":"album",
           "musicBrainzId":"","isrc":[],"genres":[{"name":"Pop"}],"replayGain":{},"channelCount":0,"samplingRate":0,
           "bitDepth":0,"moods":[],"artists":[{"id":"3a1bf0c2e4d1","name":"ABBA"}],"displayArtist":"ABBA",
           "albumArtists":[{"id":"3a1bf0c2e4d1","name":"ABBA"}],"displayAlbumArtist":"ABBA","contributors":[],
           "displayComposer":"","explicitStatus":""}],
          "id":"3a1bf0c2e4d1","name":"ABBA","albumCount":1}
        """)

    static func song(_ id: String, _ title: String, track: Int) -> String {
        """
        {"id":"\(id)","parent":"al-arrival","isDir":false,"title":"\(title)","album":"Arrival","artist":"ABBA",
         "track":\(track),"year":1976,"genre":"Pop","coverArt":"mf-\(id)_0","size":31234567,"contentType":"audio/flac",
         "suffix":"flac","duration":181,"bitRate":1012,"path":"ABBA/Arrival/0\(track) - \(title).flac","discNumber":1,
         "created":"2023-05-06T07:08:09.123456789Z","albumId":"al-arrival","artistId":"3a1bf0c2e4d1","type":"music",
         "isVideo":false,"played":"2025-01-02T03:04:05Z","bpm":0,"comment":"","sortName":"\(title.lowercased())",
         "mediaType":"song","musicBrainzId":"b1d2c3e4-0000-4000-8000-000000000001","isrc":["SEAYD7601010"],
         "genres":[{"name":"Pop"}],"replayGain":{"trackGain":-7.5,"albumGain":-8.1,"trackPeak":1,"albumPeak":1},
         "channelCount":2,"samplingRate":44100,"bitDepth":16,"moods":[],
         "artists":[{"id":"3a1bf0c2e4d1","name":"ABBA"}],"displayArtist":"ABBA",
         "albumArtists":[{"id":"3a1bf0c2e4d1","name":"ABBA"}],"displayAlbumArtist":"ABBA",
         "contributors":[{"role":"composer","artist":{"id":"c-benny","name":"Benny Andersson"}}],
         "displayComposer":"Benny Andersson","explicitStatus":""}
        """
    }

    static let arrival = ok("""
        "directory":{"child":[\(song("t1", "When I Kissed the Teacher", track: 1)),\(song("t2", "Dancing Queen", track: 2))],
          "id":"al-arrival","name":"Arrival","parent":"3a1bf0c2e4d1","playCount":12,"played":"2025-01-02T03:04:05.678Z",
          "artist":"ABBA","artistId":"3a1bf0c2e4d1","coverArt":"al-al-arrival_0","songCount":2,"duration":362,
          "created":"2023-05-06T07:08:09.123456Z","year":1976,"genre":"Pop"}
        """)

    static var bodies: [String: String] {
        [
            "getMusicFolders": musicFolders,
            "getIndexes": indexes,
            "getMusicDirectory?id=3a1bf0c2e4d1": abba,
            "getMusicDirectory?id=al-arrival": arrival,
            // An artist with nothing left in the library: Navidrome leaves "child" out.
            "getMusicDirectory?id=7f2e9a0b11c3": ok(#""directory":{"id":"7f2e9a0b11c3","name":"Björk"}"#),
        ]
    }
}

private func makeBrowser(_ transport: NavidromeFixtureTransport) -> MusicFolderBrowser {
    let client = SwiftSonicClient(
        configuration: ServerConfiguration(serverURL: URL(string: "https://music.example.com")!, username: "u", password: "p"),
        transport: transport,
        retryPolicy: .none
    )
    return MusicFolderBrowser(source: WinampSubsonicSource(client: client))
}

@Suite("Music folder browser against Navidrome")
struct MusicFolderBrowserNavidromeTests {
    @Test func swiftSonicAloneCannotReadNavidromeMusicFolders() async {
        // The cause of "Couldn't reach your server" in the Add Music browser: SwiftSonic's
        // MusicFolder wants a string ID and Navidrome sends a number.
        let client = SwiftSonicClient(
            configuration: ServerConfiguration(serverURL: URL(string: "https://music.example.com")!, username: "u", password: "p"),
            transport: NavidromeFixtureTransport(bodies: NavidromeFixtures.bodies),
            retryPolicy: .none
        )
        do {
            _ = try await client.getMusicFolders()
            Issue.record("SwiftSonic decoded numeric music folder IDs; the lenient fallback may no longer be needed")
        } catch SwiftSonicError.decoding {
        } catch {
            Issue.record("Expected a decoding error, got \(error)")
        }
    }

    @Test func librariesWithNumericIDsAreListed() async throws {
        let browser = makeBrowser(NavidromeFixtureTransport(bodies: NavidromeFixtures.bodies))
        let roots = try await browser.roots()
        #expect(roots.folders.map(\.name) == ["Music Library", "Audiobooks"])
        #expect(roots.folders.map(\.folder) == [.musicFolder(id: "1"), .musicFolder(id: "2")])
    }

    @Test func libraryListsNavidromeIndexesWithTheNumericFolderID() async throws {
        let transport = NavidromeFixtureTransport(bodies: NavidromeFixtures.bodies)
        let browser = makeBrowser(transport)
        _ = try await browser.roots()
        let library = try await browser.listing(at: .musicFolder(id: "1"))
        #expect(library.name == "Music Library")
        #expect(library.folders.map(\.name) == ["ABBA", "Björk"])
        #expect(library.folders.first?.folder == .directory(id: "3a1bf0c2e4d1"))
        #expect(transport.queries("getIndexes").first?.contains(URLQueryItem(name: "musicFolderId", value: "1")) == true)
    }

    @Test func artistAndAlbumDirectoriesDecode() async throws {
        let browser = makeBrowser(NavidromeFixtureTransport(bodies: NavidromeFixtures.bodies))
        _ = try await browser.listing(at: .musicFolder(id: "1"))
        let artist = try await browser.listing(at: .directory(id: "3a1bf0c2e4d1"))
        #expect(artist.name == "ABBA")
        // Navidrome gives an artist folder no parent; the browser knows it came from library 1.
        #expect(artist.parent == .musicFolder(id: "1"))
        #expect(artist.folders.map(\.folder) == [.directory(id: "al-arrival")])
        #expect(artist.songs.isEmpty)

        let album = try await browser.listing(at: .directory(id: "al-arrival"))
        #expect(album.parent == .directory(id: "3a1bf0c2e4d1"))
        #expect(album.songs.map(\.name) == ["When I Kissed the Teacher", "Dancing Queen"])
        let song = try #require(album.songs.first?.song)
        #expect(song.path == "ABBA/Arrival/01 - When I Kissed the Teacher.flac")
        #expect(song.duration == 181)
        #expect(song.samplingRate == 44100)
        #expect(song.replayGain?.trackGain == -7.5)
    }

    @Test func aWholeLibraryCanBeAdded() async throws {
        let browser = makeBrowser(NavidromeFixtureTransport(bodies: NavidromeFixtures.bodies))
        _ = try await browser.roots()
        let library = try await browser.allSongs(under: .musicFolder(id: "1"))
        #expect(library.songs.map(\.id) == ["t1", "t2"])
        #expect(!library.isTruncated)
    }

    @Test func musicFolderIDsMayBeNumbersOrStrings() throws {
        let numeric = try #require(MusicLibraryFolder.folders(inResponse: Data(NavidromeFixtures.musicFolders.utf8)))
        #expect(numeric == [MusicLibraryFolder(id: "1", name: "Music Library"), MusicLibraryFolder(id: "2", name: "Audiobooks")])
        let strings = NavidromeFixtures.ok(#""musicFolders":{"musicFolder":[{"id":"lib-a","name":"A"},{"id":"7"}]}"#)
        #expect(MusicLibraryFolder.folders(inResponse: Data(strings.utf8))
            == [MusicLibraryFolder(id: "lib-a", name: "A"), MusicLibraryFolder(id: "7", name: nil)])
        #expect(MusicLibraryFolder.folders(inResponse: Data(NavidromeFixtures.ok(#""musicFolders":{}"#).utf8)) == [])
        #expect(MusicLibraryFolder.folders(inResponse: Data(NavidromeFixtures.failed(code: 0, message: "x").utf8)) == nil)
        #expect(MusicLibraryFolder.folders(inResponse: Data("<html>login</html>".utf8)) == nil)
        #expect(MusicLibraryFolder.folders(inResponse: Data()) == nil)
    }

    @Test func anUnreadableListingSaysSoRatherThanUnreachable() async throws {
        let broken = NavidromeFixtures.ok(#""musicFolders":{"musicFolder":[{"id":true,"name":"Odd"}]}"#)
        let browser = makeBrowser(NavidromeFixtureTransport(bodies: ["getMusicFolders": broken]))
        do {
            _ = try await browser.roots()
            Issue.record("Expected a decoding error")
        } catch {
            let message = MusicFolderBrowserError.message(for: error)
            #expect(message == String(localized: "Your server sent a folder listing Minidisc couldn't read."))
            #expect(message != UserFacingError.serverUnreachable.displayMessage)
        }
    }

    @Test func serverErrorsAreReportedWithTheServersMessage() async throws {
        let browser = makeBrowser(NavidromeFixtureTransport(bodies: [
            "getMusicFolders": NavidromeFixtures.failed(code: 0, message: "Library scan in progress"),
        ]))
        do {
            _ = try await browser.roots()
            Issue.record("Expected a server error")
        } catch {
            #expect(MusicFolderBrowserError.message(for: error).contains("Library scan in progress"))
        }
        // Network and sign-in problems keep the app's usual messages.
        #expect(MusicFolderBrowserError.message(for: URLError(.cannotConnectToHost))
            == UserFacingError.serverUnreachable.displayMessage)
        let auth = NavidromeFixtures.failed(code: 40, message: "Wrong username or password")
        let authBrowser = makeBrowser(NavidromeFixtureTransport(bodies: ["getMusicFolders": auth]))
        do {
            _ = try await authBrowser.roots()
        } catch {
            #expect(MusicFolderBrowserError.message(for: error) == UserFacingError.authenticationFailed.displayMessage)
        }
    }
}

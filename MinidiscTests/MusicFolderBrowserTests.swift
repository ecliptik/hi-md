import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

/// Answers Subsonic folder endpoints from a fixed tree and counts requests per endpoint.
private final class FolderTreeTransport: HTTPTransport, Sendable {
    /// Directory ID → (name, parent, children as JSON objects).
    let directories: [String: (name: String, parent: String?, children: [String])]
    let indexesJSON: String
    let musicFoldersJSON: String
    private let counts = Mutex<[String: Int]>([:])

    init(directories: [String: (name: String, parent: String?, children: [String])],
         indexesJSON: String,
         musicFoldersJSON: String) {
        self.directories = directories
        self.indexesJSON = indexesJSON
        self.musicFoldersJSON = musicFoldersJSON
    }

    func requests(_ endpoint: String) -> Int { counts.withLock { $0[endpoint, default: 0] } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let endpoint = url.lastPathComponent.replacingOccurrences(of: ".view", with: "")
        counts.withLock { $0[endpoint, default: 0] += 1 }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let payload: String
        switch endpoint {
        case "getMusicFolders":
            payload = "\"musicFolders\":{\"musicFolder\":\(musicFoldersJSON)}"
        case "getIndexes":
            payload = "\"indexes\":\(indexesJSON)"
        case "getMusicDirectory":
            let id = query.first { $0.name == "id" }?.value ?? ""
            guard let directory = directories[id] else {
                payload = "\"error\":{\"code\":70,\"message\":\"Directory not found\"}"
                return Self.response(payload, status: "failed", url: url)
            }
            let parent = directory.parent.map { ",\"parent\":\"\($0)\"" } ?? ""
            payload = "\"directory\":{\"id\":\"\(id)\",\"name\":\"\(directory.name)\"\(parent),\"child\":[\(directory.children.joined(separator: ","))]}"
        default:
            payload = "\"error\":{\"code\":0,\"message\":\"unexpected \(endpoint)\"}"
            return Self.response(payload, status: "failed", url: url)
        }
        return Self.response(payload, status: "ok", url: url)
    }

    private static func response(_ payload: String, status: String, url: URL) -> (Data, HTTPURLResponse) {
        let body = "{\"subsonic-response\":{\"status\":\"\(status)\",\"version\":\"1.16.1\",\(payload)}}"
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func folder(_ id: String, _ title: String, parent: String) -> String {
    "{\"id\":\"\(id)\",\"parent\":\"\(parent)\",\"isDir\":true,\"title\":\"\(title)\"}"
}

private func track(_ id: String, _ title: String, parent: String, path: String, video: Bool = false) -> String {
    "{\"id\":\"\(id)\",\"parent\":\"\(parent)\",\"isDir\":false,\"title\":\"\(title)\",\"artist\":\"A\",\"path\":\"\(path)\",\"isVideo\":\(video)}"
}

/// Two libraries; "Music" has artists ABBA and Björk, a pinned shortcut and a loose file.
private func makeTransport() -> FolderTreeTransport {
    FolderTreeTransport(
        directories: [
            "ar-abba": ("ABBA", "root-1", [
                folder("al-arrival", "Arrival", parent: "ar-abba"),
                folder("al-gold", "Gold", parent: "ar-abba"),
            ]),
            "al-arrival": ("Arrival", "ar-abba", [
                track("t1", "When I Kissed the Teacher", parent: "al-arrival", path: "ABBA/Arrival/01.flac"),
                track("t2", "Dancing Queen", parent: "al-arrival", path: "ABBA/Arrival/02.flac"),
                track("v1", "Video", parent: "al-arrival", path: "ABBA/Arrival/v.mp4", video: true),
            ]),
            "al-gold": ("Gold", "ar-abba", [
                folder("cd2", "CD2", parent: "al-gold"),
                track("t3", "Waterloo", parent: "al-gold", path: "ABBA/Gold/01.flac"),
            ]),
            "cd2": ("CD2", "al-gold", [
                track("t4", "Fernando", parent: "cd2", path: "ABBA/Gold/CD2/01.flac"),
            ]),
            "ar-bjork": ("Björk", "root-1", [
                track("t5", "Joga", parent: "ar-bjork", path: "Bjork/02.flac"),
            ]),
        ],
        indexesJSON: """
        {"lastModified":0,"ignoredArticles":"The",
         "shortcut":[{"id":"ar-bjork","name":"Björk"}],
         "index":[{"name":"A","artist":[{"id":"ar-abba","name":"ABBA"}]},
                  {"name":"B","artist":[{"id":"ar-bjork","name":"Björk"}]}],
         "child":[{"id":"loose","isDir":false,"title":"Loose Track","path":"loose.mp3"}]}
        """,
        musicFoldersJSON: "[{\"id\":\"1\",\"name\":\"Music\"},{\"id\":\"2\",\"name\":\"Podcasts\"}]"
    )
}

private func makeBrowser(_ transport: FolderTreeTransport) -> MusicFolderBrowser {
    let client = SwiftSonicClient(
        configuration: ServerConfiguration(serverURL: URL(string: "https://stub.example.com")!, username: "u", password: "p"),
        transport: transport,
        retryPolicy: .none
    )
    return MusicFolderBrowser(source: WinampSubsonicSource(client: client))
}

/// Cancels the calling task on its first directory request, to test cancellation mid-walk.
private struct CancellingSource: MusicFolderSource {
    let base: any MusicFolderSource

    func musicFolders() async throws -> [MusicFolder] { try await base.musicFolders() }
    func indexes(musicFolderID: String?) async throws -> Indexes { try await base.indexes(musicFolderID: musicFolderID) }
    func directory(id: String) async throws -> MusicDirectory {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await base.directory(id: id)
    }
}

@Suite("Music folder browser")
struct MusicFolderBrowserTests {
    @Test func rootsListEveryLibrary() async throws {
        let browser = makeBrowser(makeTransport())
        let roots = try await browser.roots()
        #expect(roots.parent == nil)
        #expect(roots.folders.map(\.name) == ["Music", "Podcasts"])
        #expect(roots.folders.first?.folder == .musicFolder(id: "1"))
        #expect(roots.songs.isEmpty)
    }

    @Test func libraryListsArtistFoldersOnceAndLooseSongs() async throws {
        let browser = makeBrowser(makeTransport())
        _ = try await browser.roots()
        let library = try await browser.listing(at: .musicFolder(id: "1"))
        #expect(library.name == "Music")
        #expect(library.parent == .libraries)
        // Björk is both a shortcut and indexed; she appears once.
        #expect(library.folders.map(\.name) == ["Björk", "ABBA"])
        #expect(library.songs.map(\.name) == ["Loose Track"])
    }

    @Test func directoryListsFoldersThenSongsWithoutVideos() async throws {
        let browser = makeBrowser(makeTransport())
        let gold = try await browser.listing(at: .directory(id: "al-gold"))
        #expect(gold.folders.map(\.folder) == [.directory(id: "cd2")])
        #expect(gold.songs.map(\.song?.id) == ["t3"])
        #expect(gold.items.map(\.name) == ["CD2", "Waterloo"])

        let arrival = try await browser.listing(at: .directory(id: "al-arrival"))
        #expect(arrival.songs.map(\.id) == ["t1", "t2"])
        #expect(arrival.songs.first?.song?.path == "ABBA/Arrival/01.flac")
    }

    @Test func parentNavigationClimbsToTheLibrary() async throws {
        let transport = makeTransport()
        let browser = makeBrowser(transport)
        _ = try await browser.listing(at: .musicFolder(id: "1"))

        let album = try await browser.listing(at: .directory(id: "al-gold"))
        #expect(album.parent == .directory(id: "ar-abba"))
        // ABBA's server parent is an internal root ID; the browser knows it came from library 1.
        let artist = try await browser.listing(at: .directory(id: "ar-abba"))
        #expect(artist.parent == .musicFolder(id: "1"))

        let before = transport.requests("getMusicDirectory")
        #expect(try await browser.parent(of: .directory(id: "ar-abba")) == .musicFolder(id: "1"))
        #expect(transport.requests("getMusicDirectory") == before)
        #expect(try await browser.parent(of: .musicFolder(id: "1")) == .libraries)
        #expect(try await browser.parent(of: .libraries) == nil)
        #expect(try await browser.parent(of: .directory(id: "cd2")) == .directory(id: "al-gold"))
    }

    @Test func allSongsWalksDepthFirstInOrder() async throws {
        let browser = makeBrowser(makeTransport())
        let artist = try await browser.allSongs(under: .directory(id: "ar-abba"))
        // A folder's own files come before its subfolders, as when Winamp adds a directory.
        #expect(artist.songs.map(\.id) == ["t1", "t2", "t3", "t4"])
        #expect(!artist.isTruncated)

        let library = try await browser.allSongs(under: .musicFolder(id: "1"))
        #expect(library.songs.map(\.id) == ["loose", "t5", "t1", "t2", "t3", "t4"])
    }

    @Test func allSongsStopsAtTheSongLimit() async throws {
        let browser = makeBrowser(makeTransport())
        let result = try await browser.allSongs(under: .directory(id: "ar-abba"), songLimit: 3)
        #expect(result.songs.map(\.id) == ["t1", "t2", "t3"])
        #expect(result.isTruncated)
    }

    @Test func allSongsStopsAtTheFolderLimit() async throws {
        let transport = makeTransport()
        let browser = makeBrowser(transport)
        let result = try await browser.allSongs(under: .directory(id: "ar-abba"), folderLimit: 2)
        #expect(result.songs.map(\.id) == ["t1", "t2"])
        #expect(result.isTruncated)
        #expect(transport.requests("getMusicDirectory") == 2)
    }

    @Test func allSongsHonoursCancellation() async throws {
        let client = SwiftSonicClient(
            configuration: ServerConfiguration(serverURL: URL(string: "https://stub.example.com")!, username: "u", password: "p"),
            transport: makeTransport(),
            retryPolicy: .none
        )
        let browser = MusicFolderBrowser(source: CancellingSource(base: WinampSubsonicSource(client: client)))
        let task = Task { try await browser.allSongs(under: .directory(id: "ar-abba")) }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func missingDirectorySurfacesTheServerError() async {
        let browser = makeBrowser(makeTransport())
        await #expect(throws: SwiftSonicError.self) { try await browser.listing(at: .directory(id: "gone")) }
    }
}

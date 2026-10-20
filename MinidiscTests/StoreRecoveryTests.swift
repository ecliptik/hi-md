import Foundation
import Testing
@testable import Minidisc

@Suite("Persisted store recovery")
@MainActor
struct StoreRecoveryTests {
    private struct Entry: Codable, Equatable { let id: Int }

    private func directory() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("store-recovery-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A bad array entry is dropped without losing its neighbours")
    func lossyArrayKeepsGoodEntries() throws {
        let data = Data(#"[{"id":1},{"id":"two"},{"id":3}]"#.utf8)
        let decoded = try JSONStoreRecovery.decodeArray(Entry.self, from: data)
        #expect(decoded.elements == [Entry(id: 1), Entry(id: 3)])
        #expect(decoded.dropped == 1)
    }

    @Test("Data that is not an array still throws")
    func nonArrayThrows() {
        #expect(throws: (any Error).self) {
            try JSONStoreRecovery.decodeArray(Entry.self, from: Data("not json".utf8))
        }
    }

    @Test("An unreadable local music index keeps its folders and is preserved on disk")
    func localMusicIndexRecoversFolders() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderID = UUID()
        let bookmark = Data("bookmark".utf8).base64EncodedString()
        let json = """
        {"folders":[{"id":"\(folderID.uuidString)","name":"Music","bookmark":"\(bookmark)","isAccessible":true}],
         "tracks":[{"unexpected":"shape"}]}
        """
        let index = directory.appendingPathComponent("index.json")
        try Data(json.utf8).write(to: index)

        let store = LocalMusicStore(directory: directory)
        let snapshot = await store.current()

        #expect(snapshot.folders.map(\.id) == [folderID])
        #expect(snapshot.folders.first?.bookmark == Data("bookmark".utf8))
        #expect(snapshot.tracks.isEmpty)
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("index.unreadable-") }
        #expect(kept.count == 1)
    }

    @Test("A missing local music index is a normal first run")
    func missingLocalMusicIndexIsEmpty() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = await LocalMusicStore(directory: directory).current()
        #expect(snapshot.folders.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

@MainActor
private final class FlakyKeychain: KeychainServiceProtocol {
    private let base = SubmitMockKeychain()
    var failReads = false

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        try await base.store(value, forKey: key)
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        if failReads { throw MinidiscError.keychainReadFailed(-25308) }
        return try await base.retrieve(type, forKey: key)
    }

    func delete(forKey key: String) async throws { try await base.delete(forKey: key) }
}

@Suite("Scrobbling restore with an unavailable Keychain")
@MainActor
struct ScrobblingKeychainFailureTests {
    @Test("A failed Keychain read neither disables scrobbling nor discards the offline queue")
    func transientKeychainFailureKeepsState() async throws {
        let queueURL = URL.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: queueURL) }
        let enabledKey = "app.minidisc.listenbrainz.scrobbling.isEnabled"
        let validToken = Data(#"{"valid":true,"user_name":"alice"}"#.utf8)

        // First launch: configure scrobbling and queue one listen while the server is unreachable.
        let sharedKeychain = FlakyKeychain()
        let suite = "test.scrobble.\(UUID())"
        let first = ListenBrainzService(
            client: ListenBrainzClient(transport: FailingAfterValidation(validToken)),
            keychain: sharedKeychain, userDefaults: UserDefaults(suiteName: suite)!, queueFileURL: queueURL
        )
        try await first.validateAndSaveScrobblingToken("tok", rootURL: URL(string: "https://api.listenbrainz.org")!)
        await first.notifyScrobbleThreshold(song: Self.song, startDate: Date())
        #expect(await first.pendingListenCount == 1)
        #expect(UserDefaults(suiteName: suite)!.bool(forKey: enabledKey))

        // Relaunch while the Keychain cannot be read.
        sharedKeychain.failReads = true
        let relaunched = ListenBrainzService(
            client: ListenBrainzClient(transport: FailingAfterValidation(nil)),
            keychain: sharedKeychain, userDefaults: UserDefaults(suiteName: suite)!, queueFileURL: queueURL
        )
        await relaunched.loadPersistedState()

        #expect(UserDefaults(suiteName: suite)!.bool(forKey: enabledKey))
        #expect(FileManager.default.fileExists(atPath: queueURL.path))

        // The Keychain recovers: the same state loads, including the queued listen.
        sharedKeychain.failReads = false
        await relaunched.loadPersistedState()
        #expect(await relaunched.pendingListenCount == 1)
    }

    private static let song = DisplayableSong(
        id: "s1", title: "Paranoid Android", artist: "Radiohead",
        albumId: "alb1", albumName: "OK Computer", artistId: "art1",
        genre: nil, duration: 360, trackNumber: 2, isDownloaded: false,
        coverArtId: nil, audioFormat: nil,
        replayGainTrackGain: nil, replayGainTrackPeak: nil,
        replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
        replayGainBaseGain: nil, replayGainFallbackGain: nil
    )
}

/// Answers the first request (token validation) with success, then fails every later request so
/// scrobbles stay queued.
@MainActor
private final class FailingAfterValidation: ListenBrainzTransport {
    private var answeredFirst = false
    private let firstBody: Data

    /// `nil` makes every request fail.
    init(_ firstBody: Data?) {
        self.firstBody = firstBody ?? Data()
        answeredFirst = firstBody == nil
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let status = answeredFirst ? 503 : 200
        let body = answeredFirst ? Data() : firstBody
        answeredFirst = true
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

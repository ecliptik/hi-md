import Foundation
import SwiftSonic

/// The folder endpoints the Winamp "Add" browser reads. They follow the server's real directory
/// layout rather than ID3 tags.
nonisolated protocol MusicFolderSource: Sendable {
    func musicFolders() async throws -> [MusicLibraryFolder]
    func indexes(musicFolderID: String?) async throws -> Indexes
    func directory(id: String) async throws -> MusicDirectory
}

/// SwiftSonic adapter for Winamp mode's folder browser and playlist resolver. Like
/// `SwiftSonicLibrarySource`, it keeps one client per active connection version.
actor WinampSubsonicSource: MusicFolderSource, M3USongLookup {
    private let serverService: (any ServerServiceProtocol)?
    private var cachedClient: SwiftSonicClient?
    private var cachedVersion: ServerConnection.Version?
    /// Songs per search when resolving playlist entries; enough to cover a title on many albums.
    private let searchSongCount = 40

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    /// A fixed client, for tests and previews.
    init(client: SwiftSonicClient) {
        serverService = nil
        cachedClient = client
    }

    /// The server's libraries. SwiftSonic's `MusicFolder` wants a string ID, but the Subsonic spec
    /// and Navidrome send a number (`"id": 1`), which fails to decode; the response that failed
    /// is then read again with `MusicLibraryFolder`, which takes either.
    func musicFolders() async throws -> [MusicLibraryFolder] {
        do {
            return try await client().getMusicFolders().map { MusicLibraryFolder(id: $0.id, name: $0.name) }
        } catch SwiftSonicError.decoding(let error, let rawData) {
            guard let folders = MusicLibraryFolder.folders(inResponse: rawData) else {
                throw SwiftSonicError.decoding(error, rawData: rawData)
            }
            return folders
        }
    }

    func indexes(musicFolderID: String?) async throws -> Indexes {
        try await client().getIndexes(musicFolderId: musicFolderID)
    }

    func directory(id: String) async throws -> MusicDirectory {
        try await client().getMusicDirectory(id: id)
    }

    func song(id: String) async throws -> Song? {
        do {
            return try await client().getSong(id: id)
        } catch SwiftSonicError.api(let error) where error.code == .notFound {
            return nil
        }
    }

    func searchSongs(_ query: String) async throws -> [Song] {
        try await client().search3(query, artistCount: 0, albumCount: 0, songCount: searchSongCount).song ?? []
    }

    private func client() async throws -> SwiftSonicClient {
        guard let serverService else {
            guard let cachedClient else { throw MinidiscError.notImplemented }
            return cachedClient
        }
        let activeVersion = await serverService.activeConnectionVersion()
        if let cachedClient, let activeVersion, cachedVersion == activeVersion {
            return cachedClient
        }
        let connection = try await serverService.activeConnection()
        let fresh = connection.makeSwiftSonicClient()
        cachedClient = fresh
        cachedVersion = connection.version
        return fresh
    }
}

import Foundation
import SwiftSonic

/// The folder endpoints the Winamp "Add" browser reads. They follow the server's real directory
/// layout rather than ID3 tags.
nonisolated protocol MusicFolderSource: Sendable {
    func musicFolders() async throws -> [MusicFolder]
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

    func musicFolders() async throws -> [MusicFolder] {
        try await client().getMusicFolders()
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

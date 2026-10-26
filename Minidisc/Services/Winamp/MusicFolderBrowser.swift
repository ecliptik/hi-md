import Foundation
import SwiftSonic

/// A place in the server's folder tree.
nonisolated enum MusicFolderLocation: Sendable, Hashable {
    /// Every music folder (library) on the server.
    case libraries
    /// The top level of one library, from `getIndexes`.
    case musicFolder(id: String)
    /// Any folder below that, from `getMusicDirectory`.
    case directory(id: String)
}

nonisolated struct MusicFolderItem: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        case folder(MusicFolderLocation)
        case song(Song)
    }

    let id: String
    let name: String
    let kind: Kind

    var song: Song? {
        if case .song(let song) = kind { song } else { nil }
    }

    var folder: MusicFolderLocation? {
        if case .folder(let location) = kind { location } else { nil }
    }
}

/// One folder's contents, folders first, both in server order.
nonisolated struct MusicFolderListing: Sendable {
    let location: MusicFolderLocation
    let name: String
    /// Nil only at `.libraries`.
    let parent: MusicFolderLocation?
    let folders: [MusicFolderItem]
    let songs: [MusicFolderItem]

    var items: [MusicFolderItem] { folders + songs }
}

/// The songs found under a folder, in folder order.
nonisolated struct MusicFolderSongs: Sendable {
    let songs: [Song]
    /// True when the walk stopped at the song or folder limit.
    let isTruncated: Bool
}

/// Browses Navidrome like a file system: libraries, then artist folders, album folders and tracks.
/// It remembers which library each top-level folder came from, because the server reports
/// those folders' parent as an internal root ID rather than the library.
actor MusicFolderBrowser {
    static let defaultSongLimit = 5_000
    static let defaultFolderLimit = 2_000

    private let source: any MusicFolderSource
    private var libraryNames: [String: String] = [:]
    /// Top-level folder ID → the library it was listed under.
    private var topLevelLibrary: [String: String] = [:]

    init(source: any MusicFolderSource) {
        self.source = source
    }

    func roots() async throws -> MusicFolderListing {
        try await listing(at: .libraries)
    }

    func listing(at location: MusicFolderLocation) async throws -> MusicFolderListing {
        switch location {
        case .libraries:
            let folders = try await source.musicFolders()
            for folder in folders { libraryNames[folder.id] = folder.name }
            let items = folders.map {
                MusicFolderItem(id: $0.id, name: $0.name ?? $0.id, kind: .folder(.musicFolder(id: $0.id)))
            }
            return MusicFolderListing(location: location, name: "", parent: nil, folders: items, songs: [])

        case .musicFolder(let id):
            let indexes = try await source.indexes(musicFolderID: id)
            let artists = (indexes.shortcut?.map { ($0.id, $0.name) } ?? [])
                + (indexes.index ?? []).flatMap { $0.artist.map { ($0.id, $0.name) } }
            var seen = Set<String>()
            var folders: [MusicFolderItem] = []
            for (folderID, name) in artists where seen.insert(folderID).inserted {
                topLevelLibrary[folderID] = id
                folders.append(MusicFolderItem(id: folderID, name: name, kind: .folder(.directory(id: folderID))))
            }
            return MusicFolderListing(
                location: location,
                name: libraryNames[id] ?? id,
                parent: .libraries,
                folders: folders,
                songs: Self.songItems(indexes.child ?? [])
            )

        case .directory(let id):
            let directory = try await source.directory(id: id)
            let children = directory.child ?? []
            let folders = children.filter { $0.isDir == true }.map {
                MusicFolderItem(id: $0.id, name: $0.title, kind: .folder(.directory(id: $0.id)))
            }
            return MusicFolderListing(
                location: location,
                name: directory.name,
                parent: parent(ofDirectory: id, serverParent: directory.parent),
                folders: folders,
                songs: Self.songItems(children)
            )
        }
    }

    /// The folder above `location`, without a request when the browser has seen it.
    func parent(of location: MusicFolderLocation) async throws -> MusicFolderLocation? {
        switch location {
        case .libraries: return nil
        case .musicFolder: return .libraries
        case .directory(let id):
            if let library = topLevelLibrary[id] { return .musicFolder(id: library) }
            return try await listing(at: location).parent
        }
    }

    /// Every song below `location`, depth first: each folder's own songs, then its subfolders in
    /// listing order, as Winamp adds a directory. Stops at `songLimit` songs or
    /// `folderLimit` folder requests and checks for cancellation before each request.
    func allSongs(
        under location: MusicFolderLocation,
        songLimit: Int = defaultSongLimit,
        folderLimit: Int = defaultFolderLimit
    ) async throws -> MusicFolderSongs {
        var songs: [Song] = []
        var requests = 0
        var visited = Set<MusicFolderLocation>()
        var stack: [MusicFolderLocation] = [location]
        while let next = stack.popLast() {
            try Task.checkCancellation()
            guard visited.insert(next).inserted else { continue }
            guard requests < folderLimit else { return MusicFolderSongs(songs: songs, isTruncated: true) }
            requests += 1
            let listing = try await listing(at: next)
            for item in listing.songs {
                guard let song = item.song else { continue }
                guard songs.count < songLimit else { return MusicFolderSongs(songs: songs, isTruncated: true) }
                songs.append(song)
            }
            // Reversed so the first folder is popped first.
            stack.append(contentsOf: listing.folders.reversed().compactMap(\.folder))
        }
        return MusicFolderSongs(songs: songs, isTruncated: false)
    }

    private func parent(ofDirectory id: String, serverParent: String?) -> MusicFolderLocation {
        if let library = topLevelLibrary[id] { return .musicFolder(id: library) }
        if let serverParent, !serverParent.isEmpty { return .directory(id: serverParent) }
        if libraryNames.count == 1, let only = libraryNames.keys.first { return .musicFolder(id: only) }
        return .libraries
    }

    /// Audio files only: folders are listed separately and videos can't be queued.
    private static func songItems(_ children: [Song]) -> [MusicFolderItem] {
        children.filter { $0.isDir != true && $0.isVideo != true }.map {
            MusicFolderItem(id: $0.id, name: $0.title, kind: .song($0))
        }
    }
}

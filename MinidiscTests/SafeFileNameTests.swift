import Foundation
import SwiftData
import Testing
@testable import Minidisc

@Suite("Safe file names for server IDs")
struct SafeFileNameTests {
    private let root = URL(fileURLWithPath: "/tmp/minidisc-safe-names/downloads", isDirectory: true)

    @Test(arguments: ["al-1234", "2b8f0c1e7d6a4f3b9e21c0d4a5b6c7d8", "Track 01 (Live)", "ñandú", "a.b", "song@thumb"])
    func ordinaryIDsKeepTheirNames(id: String) {
        // Existing downloads and covers were saved under the raw ID; they must still be found.
        #expect(SafeFileName.forID(id) == id)
    }

    @Test(arguments: [
        "../../Library/Application Support/default.store", "/etc/passwd", "a/b", "a\\b", ".", "..", "",
        "a\u{0}b", String(repeating: "x", count: 201), "id-sha256-0000",
    ])
    func unsafeIDsAreHashed(id: String) {
        let name = SafeFileName.forID(id)
        #expect(name != id)
        #expect(name.hasPrefix(SafeFileName.hashedPrefix))
        #expect(name.count == SafeFileName.hashedPrefix.count + 64)
        #expect(!name.contains("/") && !name.contains("\\"))
        #expect(SafeFileName.forID(id) == name)
    }

    @Test func differentUnsafeIDsGetDifferentNames() {
        #expect(SafeFileName.forID("../a") != SafeFileName.forID("../b"))
    }

    @Test(arguments: ["../outside.mp3", "server/../../outside.mp3", "/etc/passwd", "server//song.mp3", "./song.mp3", ""])
    func relativePathsThatLeaveTheFolderAreRejected(path: String) {
        #expect(SafeFileName.url(forRelativePath: path, in: root) == nil)
    }

    @Test func relativePathInsideTheFolderResolvesThere() throws {
        let url = try #require(SafeFileName.url(forRelativePath: "server/song.flac", in: root))
        #expect(url == root.appendingPathComponent("server/song.flac"))
    }

    @Test func onlyKnownAudioExtensionsAreUsed() {
        #expect(SafeFileName.audioExtension("FLAC") == "flac")
        #expect(SafeFileName.audioExtension("mpeg") == "mpeg")
        #expect(SafeFileName.audioExtension("../../x") == nil)
        #expect(SafeFileName.audioExtension("sh") == nil)
        #expect(SafeFileName.audioExtension(nil) == nil)
    }

    @Test func ordinaryDownloadKeepsTheNameEarlierBuildsUsed() {
        let server = UUID()
        #expect(DownloadService.downloadRelativePath(songId: "tr-42", serverId: server, fileExtension: "flac")
            == "\(server.uuidString)/tr-42.flac")
    }

    @Test func traversalSongIDStaysInsideItsServerFolder() throws {
        let server = UUID()
        let path = DownloadService.downloadRelativePath(
            songId: "../../../Library/Application Support/default.store", serverId: server, fileExtension: "flac"
        )
        let url = try #require(SafeFileName.url(forRelativePath: path, in: root))
        #expect(url.deletingLastPathComponent() == root.appendingPathComponent(server.uuidString, isDirectory: true))
    }

    @Test(arguments: ["../../../Library/Preferences/x.plist@hero", "../coverarts-other", "/tmp/x"])
    func coverFilesStayInsideTheCoverFolder(id: String) throws {
        let url = try #require(DownloadService.coverURL(forId: id, in: root))
        #expect(url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
    }
}

/// Lays files out the way earlier builds did, in a private folder standing in for `Documents/app.minidisc`.
@Suite("Download and cover files after the safe-name upgrade", .serialized)
@MainActor
struct SafeFileNameUpgradeTests {
    private let base = URL.temporaryDirectory.appendingPathComponent("minidisc-safe-names-\(UUID().uuidString)", isDirectory: true)

    private func makeService() throws -> (DownloadService, ModelContainer) {
        let container = try ModelContainer.minidisc(inMemory: true)
        let service = DownloadService(
            serverService: MockServerService(), modelContainer: container, toastService: ToastService(),
            rootDirectory: base
        )
        return (service, container)
    }

    private func insertTrack(_ container: ModelContainer, songId: String, serverId: UUID, filePath: String, size: Int64) throws {
        container.mainContext.insert(DownloadedTrack(
            songId: songId, serverId: serverId, albumId: nil, filePath: filePath, fileSize: size,
            mimeType: "audio/mpeg", title: "Track", artist: "Artist", album: "Album", trackNumber: 1
        ))
        try container.mainContext.save()
    }

    @Test func downloadSavedByAnEarlierBuildIsStillFound() async throws {
        let (service, container) = try makeService()
        let server = UUID(), songId = "tr-\(UUID().uuidString)"
        let file = base.appendingPathComponent("downloads/\(server.uuidString)/\(songId).mp3")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: file)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try insertTrack(container, songId: songId, serverId: server, filePath: "\(server.uuidString)/\(songId).mp3", size: 64)

        let url = try #require(await service.downloadedURL(forSongId: songId, serverId: server))
        #expect(url.standardizedFileURL == file.standardizedFileURL)
    }

    @Test func recordPointingOutsideTheDownloadsFolderIsIgnored() async throws {
        let (service, container) = try makeService()
        let server = UUID(), name = "outside-\(UUID().uuidString).mp3"
        // A file the record could reach through `..` if the path were trusted.
        let outside = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try insertTrack(container, songId: "evil", serverId: server, filePath: "../\(name)", size: 64)

        #expect(await service.downloadedURL(forSongId: "evil", serverId: server) == nil)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func coverSavedByAnEarlierBuildIsStillFound() async throws {
        let (service, _) = try makeService()
        let id = "al-\(UUID().uuidString)"
        let file = base.appendingPathComponent("coverarts/\(id)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let url = try #require(await service.localCoverArtURL(forId: id))
        #expect(url.standardizedFileURL == file.standardizedFileURL)
    }

    @Test func traversalCoverIDIsWrittenAndRemovedInsideTheCoverFolder() async throws {
        let (service, _) = try makeService()
        let target = "minidisc-traversal-\(UUID().uuidString)"
        let id = "../\(target)"
        await service.persistCover(Data([1, 2, 3]), forId: id)
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent(target).path))

        let url = try #require(await service.localCoverArtURL(forId: id))
        #expect(url.deletingLastPathComponent().standardizedFileURL
            == base.appendingPathComponent("coverarts", isDirectory: true).standardizedFileURL)
        #expect(url.lastPathComponent == SafeFileName.forID(id))
        await service.removeCover(forId: id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

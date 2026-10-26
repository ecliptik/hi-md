import Foundation
import SwiftData
import Testing
@testable import Minidisc

// Serialized: these tests share the real cover folder, and clearAllCovers() deletes it wholesale.
@Suite("User cover persistence", .serialized)
@MainActor
struct UserCoverPersistenceTests {
    private func makeService() throws -> DownloadService {
        DownloadService(
            serverService: MockServerService(),
            modelContainer: try ModelContainer.minidisc(inMemory: true),
            toastService: ToastService()
        )
    }

    private func removeUserCover(_ id: String) {
        let url = URL.documentsDirectory.appendingPathComponent("app.minidisc/playlistcovers/\(id)")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("A user cover survives clearing the cover cache")
    func userCoverSurvivesClearAll() async throws {
        let service = try makeService()
        let userID = "playlist-\(UUID())@thumb"
        let cachedID = "album-\(UUID())@thumb"
        defer { removeUserCover(userID) }

        await service.persistUserCover(Data("custom".utf8), forId: userID)
        await service.persistCover(Data("server".utf8), forId: cachedID)
        await service.clearAllCovers()

        let kept = try #require(await service.localCoverArtURL(forId: userID))
        #expect(try Data(contentsOf: kept) == Data("custom".utf8))
        #expect(await service.localCoverArtURL(forId: cachedID) == nil)
    }

    @Test("A cover cached by an earlier version is adopted and then survives clearing")
    func legacyCoverIsAdopted() async throws {
        let service = try makeService()
        let id = "playlist-\(UUID())@hero"
        defer { removeUserCover(id) }

        await service.persistCover(Data("legacy".utf8), forId: id)
        await service.adoptLegacyUserCover(forId: id)
        await service.clearAllCovers()

        let kept = try #require(await service.localCoverArtURL(forId: id))
        #expect(try Data(contentsOf: kept) == Data("legacy".utf8))
    }

    @Test("Adopting never replaces a cover the user already chose")
    func adoptionKeepsExistingUserCover() async throws {
        let service = try makeService()
        let id = "playlist-\(UUID())@thumb"
        defer { removeUserCover(id) }

        await service.persistUserCover(Data("chosen".utf8), forId: id)
        await service.persistCover(Data("stale".utf8), forId: id)
        await service.adoptLegacyUserCover(forId: id)

        let url = try #require(await service.localCoverArtURL(forId: id))
        #expect(try Data(contentsOf: url) == Data("chosen".utf8))
        await service.removeCover(forId: id)
    }
}

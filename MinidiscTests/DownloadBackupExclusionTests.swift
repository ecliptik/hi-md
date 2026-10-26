import Foundation
import SwiftData
import Testing
@testable import Minidisc

@Suite("Download folders and backups")
@MainActor
struct DownloadBackupExclusionTests {
    private let base = URL.temporaryDirectory.appendingPathComponent("minidisc-backup-\(UUID().uuidString)", isDirectory: true)

    private func makeService() throws -> DownloadService {
        DownloadService(
            serverService: MockServerService(), modelContainer: try ModelContainer.minidisc(inMemory: true),
            toastService: ToastService(), rootDirectory: base
        )
    }

    private func isExcluded(_ folder: String) throws -> Bool {
        let values = try base.appendingPathComponent(folder, isDirectory: true)
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        return values.isExcludedFromBackup == true
    }

    @Test func downloadsAndServerCoversAreExcludedAtLaunch() async throws {
        let service = try makeService()
        defer { try? FileManager.default.removeItem(at: base) }
        await service.excludeDownloadsFromBackup()
        #expect(try isExcluded("downloads"))
        #expect(try isExcluded("coverarts"))
    }

    @Test func coverCacheRecreatedAfterAWipeIsExcludedAgain() async throws {
        let service = try makeService()
        defer { try? FileManager.default.removeItem(at: base) }
        await service.persistCover(Data([1]), forId: "al-1")
        #expect(try isExcluded("coverarts"))
        await service.clearAllCovers()
        await service.persistCover(Data([1]), forId: "al-1")
        #expect(try isExcluded("coverarts"))
    }

    @Test func userChosenPlaylistCoversStayInBackups() async throws {
        let service = try makeService()
        defer { try? FileManager.default.removeItem(at: base) }
        await service.persistUserCover(Data([1]), forId: "pl-1")
        #expect(try !isExcluded("playlistcovers"))
    }
}

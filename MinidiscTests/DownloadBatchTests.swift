import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

/// Fails every transfer as soon as it starts.
private actor FailingDownloadTransport: DownloadTransport {
    nonisolated let events: AsyncStream<DownloadTransportEvent>
    private let channel: AsyncStream<DownloadTransportEvent>.Continuation
    private(set) var startedRequests = 0

    init() {
        let stream = AsyncStream<DownloadTransportEvent>.makeStream()
        events = stream.stream
        channel = stream.continuation
    }

    func activeJobIDs() async -> Set<UUID> { [] }
    func start(jobID: UUID, request: URLRequest) async {
        startedRequests += 1
        channel.yield(.failed(jobID, .downloadFailed))
    }
    func cancel(jobID: UUID) async {}
    func completedTransfers() async -> [CompletedDownload] { [] }
    func fileURL(jobID: UUID) async -> URL { URL.temporaryDirectory.appendingPathComponent(jobID.uuidString) }
    func acknowledge(jobID: UUID) async {}
}

@Suite("Batch downloads for playlists", .timeLimit(.minutes(1)))
@MainActor
struct DownloadBatchTests {
    @Test func everySongIsTriedAndOnlyTheFailuresAreReturned() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("minidisc-batch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let serverID = UUID()
        let server = MockServerService()
        server.connection = try ServerConnection(
            version: .init(serverID: serverID, revision: 1),
            server: ServerSnapshot(from: ServerConfig(id: serverID, displayName: "Test", baseURL: "https://download.invalid", username: "test")),
            credentials: .init(password: "secret", customHeaders: [:])
        )
        let container = try ModelContainer.minidisc(inMemory: true)
        let transport = FailingDownloadTransport()
        let service = DownloadService(
            serverService: server, modelContainer: container, toastService: ToastService(),
            transferTransport: transport, journalURL: root.appendingPathComponent("queue.json"), rootDirectory: root
        )

        // "kept" is already on disk, so it is skipped rather than downloaded again.
        let keptFile = root.appendingPathComponent("downloads/\(serverID.uuidString)/kept.mp3")
        try FileManager.default.createDirectory(at: keptFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16).write(to: keptFile)
        container.mainContext.insert(DownloadedTrack(
            songId: "kept", serverId: serverID, albumId: nil, filePath: "\(serverID.uuidString)/kept.mp3",
            fileSize: 16, mimeType: "audio/mpeg", title: "Kept", artist: "Artist", album: "Album", trackNumber: 1
        ))
        try container.mainContext.save()

        let songs = try ["kept", "missing-1", "missing-2"].map {
            try JSONDecoder().decode(Song.self, from: Data("{\"id\":\"\($0)\",\"title\":\"Track\",\"isDir\":false,\"duration\":10}".utf8))
        }
        let failures = await service.download(songs: songs, serverId: serverID)

        #expect(Set(failures.map { $0.songId }) == ["missing-1", "missing-2"])
        #expect(await transport.startedRequests == 2)
    }
}

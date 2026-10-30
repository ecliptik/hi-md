import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

private actor SlowFavoriteEditor: FavoriteEditing {
    private var release: CheckedContinuation<Void, Never>?
    private var holds = false
    func hold() { holds = true }
    func finish() { release?.resume(); release = nil; holds = false }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        await withCheckedContinuation { if holds { release = $0 } else { $0.resume() } }
    }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func getStarred2() async throws -> Starred2 { throw URLError(.timedOut) }
}

@Suite @MainActor
struct FavoritesReconcileTests {
    private static func starred(songs: [String]) throws -> Starred2 {
        let list = songs.map { #"{"id":"\#($0)","title":"\#($0)","isDir":false}"# }.joined(separator: ",")
        return try JSONDecoder().decode(Starred2.self, from: Data(#"{"song":[\#(list)]}"#.utf8))
    }

    private static func songIDs(_ container: ModelContainer) throws -> Set<String> {
        Set(try ModelContext(container).fetch(FetchDescriptor<FavoriteRecord>()).map(\.itemId))
    }

    private static func makeService(_ editor: SlowFavoriteEditor = SlowFavoriteEditor()) throws
        -> (FavoritesService, ModelContainer, UUID) {
        let container = try ModelContainer.minidisc(inMemory: true)
        let state = ServerState()
        let server = ServerSnapshot(from: ServerConfig(displayName: "Test", baseURL: "https://example.invalid", username: "test"))
        state.activeServer = server
        return (FavoritesService(libraryService: editor, serverState: state, modelContainer: container), container, server.id)
    }

    @Test func aFetchedStarredListBecomesTheHearts() async throws {
        let (service, container, serverID) = try Self.makeService()
        try await service.reconcile(with: Self.starred(songs: ["jonas", "butterfly"]), serverID: serverID, requestedAt: Date())
        #expect(try Self.songIDs(container) == ["jonas", "butterfly"])
        try await service.reconcile(with: Self.starred(songs: ["jonas"]), serverID: serverID, requestedAt: Date())
        #expect(try Self.songIDs(container) == ["jonas"])
    }

    @Test func aListRequestedBeforeAStarDoesNotUndoIt() async throws {
        let (service, container, serverID) = try Self.makeService()
        let requestedAt = Date()
        try await service.star(itemType: .song, itemId: "jonas")
        try await service.reconcile(with: Self.starred(songs: []), serverID: serverID, requestedAt: requestedAt)
        #expect(try Self.songIDs(container) == ["jonas"])
    }

    @Test func aListArrivingWhileAStarIsOnItsWayDoesNotUndoIt() async throws {
        let editor = SlowFavoriteEditor()
        await editor.hold()
        let (service, container, serverID) = try Self.makeService(editor)
        let starring = Task { try await service.star(itemType: .song, itemId: "jonas") }
        while try Self.songIDs(container).isEmpty { await Task.yield() }
        try await service.reconcile(with: Self.starred(songs: []), serverID: serverID, requestedAt: Date())
        #expect(try Self.songIDs(container) == ["jonas"])
        await editor.finish()
        try await starring.value
    }

    @Test func anotherServersListIsIgnored() async throws {
        let (service, container, _) = try Self.makeService()
        await #expect(throws: CancellationError.self) {
            try await service.reconcile(with: Self.starred(songs: ["jonas"]), serverID: UUID(), requestedAt: Date())
        }
        #expect(try Self.songIDs(container).isEmpty)
    }
}

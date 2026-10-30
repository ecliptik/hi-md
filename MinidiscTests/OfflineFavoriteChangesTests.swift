import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

/// Records what reaches the "server", and can be cut off.
private actor RecordingFavoriteEditor: FavoriteEditing {
    private(set) var stars: [[String]] = []
    private(set) var unstars: [[String]] = []
    var failure: (any Error)?
    func setFailure(_ error: (any Error)?) { failure = error }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        if let failure { throw failure }
        stars.append(songIds + albumIds + artistIds)
    }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        if let failure { throw failure }
        unstars.append(songIds + albumIds + artistIds)
    }
    func getStarred2() async throws -> Starred2 { throw URLError(.notConnectedToInternet) }
}

@Suite("Favourites while offline") @MainActor
struct OfflineFavoriteChangesTests {
    private struct Harness {
        let container: ModelContainer
        let state = ServerState()
        let editor = RecordingFavoriteEditor()
        let outbox: FavoriteOutbox
        let service: FavoritesService
        let directory = URL.temporaryDirectory.appendingPathComponent("outbox-\(UUID())")

        init() throws {
            container = try ModelContainer.minidisc(inMemory: true)
            state.activeServer = ServerSnapshot(from: ServerConfig(displayName: "Test", baseURL: "https://example.invalid", username: "test"))
            outbox = FavoriteOutbox(directory: directory)
            service = FavoritesService(libraryService: editor, serverState: state, modelContainer: container, outbox: outbox)
        }

        var hearts: Set<String> {
            Set((try? ModelContext(container).fetch(FetchDescriptor<FavoriteRecord>()))?.map(\.itemId) ?? [])
        }

        func starred(_ ids: [String]) throws -> Starred2 {
            let songs = ids.map { #"{"id":"\#($0)","title":"\#($0)","isDir":false}"# }.joined(separator: ",")
            return try JSONDecoder().decode(Starred2.self, from: Data(#"{"song":[\#(songs)]}"#.utf8))
        }
    }

    @Test func offlineHeartsChangeAtOnceAndAreSentWhenBackOnline() async throws {
        let h = try Harness()
        h.state.isOnline = false
        try await h.service.star(itemType: .song, itemId: "new")
        try await h.service.star(itemType: .song, itemId: "old")
        try await h.service.unstar(itemType: .song, itemId: "old")
        #expect(h.hearts == ["new"])
        #expect(await h.editor.stars.isEmpty)

        h.state.isOnline = true
        await h.service.flushPending()
        #expect(await h.editor.stars == [["new"]])
        #expect(await h.editor.unstars == [["old"]], "the later unstar replaced the queued star")
        #expect(await h.outbox.pending(serverID: h.state.activeServer!.id).isEmpty)
    }

    @Test func aDroppedConnectionQueuesInsteadOfUndoing() async throws {
        let h = try Harness()
        h.state.isOnline = true
        await h.editor.setFailure(URLError(.timedOut))
        try await h.service.star(itemType: .song, itemId: "s1")
        #expect(h.hearts == ["s1"])
        #expect(await h.outbox.pending(serverID: h.state.activeServer!.id).map(\.itemID) == ["s1"])

        // Still unreachable: the change stays queued for the next try.
        await h.service.flushPending()
        #expect(await h.outbox.pending(serverID: h.state.activeServer!.id).count == 1)
        await h.editor.setFailure(nil)
        await h.service.flushPending()
        #expect(await h.editor.stars == [["s1"]])
    }

    @Test func theServersListDoesntUndoQueuedChanges() async throws {
        let h = try Harness()
        h.state.isOnline = true
        try await h.service.reconcile(with: h.starred(["kept", "unstarred"]), serverID: h.state.activeServer!.id,
                                      requestedAt: .now)
        h.state.isOnline = false
        try await h.service.unstar(itemType: .song, itemId: "unstarred")
        try await h.service.star(itemType: .song, itemId: "starred")
        // A list from before the changes, as an offline snapshot would be.
        try await h.service.reconcile(with: h.starred(["kept", "unstarred"]), serverID: h.state.activeServer!.id,
                                      requestedAt: .now.addingTimeInterval(60))
        #expect(h.hearts == ["kept", "starred"])
    }

    @Test func theQueueSurvivesARelaunch() async throws {
        let h = try Harness()
        h.state.isOnline = false
        try await h.service.star(itemType: .album, itemId: "a1")
        let reopened = FavoriteOutbox(directory: h.directory)
        #expect(await reopened.pending(serverID: h.state.activeServer!.id).map(\.recordID) == ["album:a1"])
    }

    @Test func aRefusedQueuedChangeIsDroppedNotRetriedForever() async throws {
        let h = try Harness()
        h.state.isOnline = false
        try await h.service.star(itemType: .song, itemId: "deleted")
        h.state.isOnline = true
        await h.editor.setFailure(SwiftSonicError.httpError(statusCode: 404, endpoint: "star", serverHost: nil))
        await h.service.flushPending()
        #expect(await h.outbox.pending(serverID: h.state.activeServer!.id).isEmpty)
    }
}

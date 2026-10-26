import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

private actor RecordingFavoriteEditor: FavoriteEditing {
    private(set) var starredAlbums: [String] = []
    private(set) var unstarredAlbums: [String] = []

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        starredAlbums += albumIds
    }

    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        unstarredAlbums += albumIds
    }

    func getStarred2() async throws -> Starred2 { throw URLError(.timedOut) }
}

@Suite("Favourite heart toggle")
@MainActor
struct FavoriteToggleTests {
    @Test func anUnstarredItemOffersToAdd() {
        let toggle = FavoriteToggle(isFavorite: false)
        #expect(toggle.systemImage == "heart")
        #expect(toggle.menuSystemImage == "heart")
        #expect(toggle.toggled)
        #expect(String(localized: toggle.actionTitle) == String(localized: "Add to Favorites"))
        #expect(String(localized: toggle.accessibilityValue) == String(localized: "Off"))
    }

    @Test func aStarredItemOffersToRemove() {
        let toggle = FavoriteToggle(isFavorite: true)
        #expect(toggle.systemImage == "heart.fill")
        #expect(toggle.menuSystemImage == "heart.slash")
        #expect(!toggle.toggled)
        #expect(String(localized: toggle.actionTitle) == String(localized: "Remove from Favorites"))
        #expect(String(localized: toggle.accessibilityValue) == String(localized: "On"))
    }

    @Test func everyAppUsesHeartsForTheSameStates() {
        #expect(FavoriteToggle(isFavorite: false).systemImage == "heart")
        #expect(FavoriteToggle(isFavorite: true).systemImage == "heart.fill")
        #expect(FavoriteToggle(isFavorite: false).menuSystemImage == "heart")
        #expect(FavoriteToggle(isFavorite: true).menuSystemImage == "heart.slash")
    }

    @Test func recordIDsMatchTheStore() {
        #expect(FavoriteToggle.recordID(.album, id: "al-1") == "album:al-1")
        #expect(FavoriteToggle.recordID(.artist, id: "ar-1") == "artist:ar-1")
        #expect(FavoriteToggle.recordID(.song, id: "so-1") == "song:so-1")
        let record = FavoriteRecord(itemType: .album, itemId: "al-1", starredDate: .now, serverId: UUID())
        #expect(record.id == FavoriteToggle.recordID(.album, id: "al-1"))
    }

    /// The header heart and the … menu both read the album's FavoriteRecord, so starring from
    /// either one flips the other.
    @Test func starringAnAlbumFlipsTheSharedRecord() async throws {
        let container = try ModelContainer.minidisc(inMemory: true)
        let state = ServerState()
        state.activeServer = ServerSnapshot(from: ServerConfig(displayName: "Test", baseURL: "https://example.invalid", username: "test"))
        let editor = RecordingFavoriteEditor()
        let service = FavoritesService(libraryService: editor, serverState: state, modelContainer: container)
        let recordID = FavoriteToggle.recordID(.album, id: "al-1")
        func toggle() throws -> FavoriteToggle {
            let count = try container.mainContext.fetchCount(FetchDescriptor<FavoriteRecord>(
                predicate: #Predicate { $0.id == recordID }))
            return FavoriteToggle(isFavorite: count > 0)
        }

        #expect(try !toggle().isFavorite)
        try await service.star(itemType: .album, itemId: "al-1")
        #expect(try toggle().isFavorite)
        #expect(service.isFavorite(itemType: .album, itemId: "al-1"))
        try await service.unstar(itemType: .album, itemId: "al-1")
        #expect(try !toggle().isFavorite)
        #expect(await editor.starredAlbums == ["al-1"])
        #expect(await editor.unstarredAlbums == ["al-1"])
    }
}

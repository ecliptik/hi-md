import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Home personalization")
@MainActor
struct HomePersonalizationTests {
    private struct Starred { let id: String; let starred: Date? }

    @Test("Heavy rotation is what's been played a lot lately, not an old favourite")
    func heavyRotationIsRecent() throws {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let day: TimeInterval = 86_400
        func album(_ id: String, plays: Int, playedDaysAgo: Double?) -> AlbumID3 {
            AlbumID3(id: id, name: id, songCount: 10, duration: 2400, playCount: plays,
                     played: playedDaysAgo.map { now.addingTimeInterval(-$0 * day) })
        }
        let mostPlayed = [
            album("pogues", plays: 300, playedDaysAgo: 200),
            album("rentals", plays: 40, playedDaysAgo: 10),
            album("blur", plays: 90, playedDaysAgo: 3),
            album("ash", plays: 60, playedDaysAgo: 30),
            album("starred", plays: 80, playedDaysAgo: 1),
        ]
        let rotation = HomePersonalization.heavyRotation(mostPlayed, excluding: ["starred"], now: now)
        #expect(rotation.map(\.id) == ["blur", "ash", "rentals"])

        // Without play dates, as on plain Subsonic servers, the list stays as the server ranks it.
        let undated = [album("a", plays: 5, playedDaysAgo: nil), album("b", plays: 9, playedDaysAgo: nil)]
        #expect(HomePersonalization.heavyRotation(undated, excluding: [], now: now).map(\.id) == ["a", "b"])
    }

    @Test("Favourites come newest first, in the same order every time")
    func favouritesNewestFirst() {
        let items = [
            Starred(id: "old", starred: Date(timeIntervalSince1970: 100)),
            Starred(id: "undated", starred: nil),
            Starred(id: "new-b", starred: Date(timeIntervalSince1970: 300)),
            Starred(id: "middle", starred: Date(timeIntervalSince1970: 200)),
            Starred(id: "new-a", starred: Date(timeIntervalSince1970: 300))
        ]
        let ordered = HomeFavorites.newestFirst(items, starred: \.starred, id: \.id, limit: .max).map(\.id)
        #expect(ordered == ["new-a", "new-b", "middle", "old", "undated"])
        // Whatever order the server sends them in.
        #expect(HomeFavorites.newestFirst(items.reversed(), starred: \.starred, id: \.id, limit: .max).map(\.id) == ordered)
        #expect(HomeFavorites.newestFirst(items, starred: \.starred, id: \.id, limit: 2).map(\.id) == ["new-a", "new-b"])
    }

    @Test("Rediscovery removes duplicates and the latest listening history")
    func rediscovery() throws {
        let a = try album("a", artistID: "artist")
        let b = try album("b", artistID: "artist")
        let c = try album("c", artistID: "artist")
        #expect(HomePersonalization.rediscovery(favorites: [a, b], frequent: [b, c], recent: [a]).map(\.id) == ["b", "c"])
    }

    @Test("Relevant additions use favorite artists and listening habits without inventing matches")
    func relevantArtists() throws {
        let favorite = try album("favorite", artistID: "favorite-artist")
        let familiar = try album("familiar", artistID: "frequent-artist")
        let newFavorite = try album("new-favorite", artistID: "favorite-artist")
        let newFamiliar = try album("new-familiar", artistID: "frequent-artist")
        let stranger = try album("stranger", artistID: "another-artist")
        let result = HomePersonalization.relevantAdditions([newFavorite, stranger, newFamiliar, newFavorite],
            favorites: HomeFavorites(albums: [favorite]), frequent: [familiar])
        #expect(result.map(\.id) == ["new-favorite", "new-familiar"])
    }

    @Test("Artist names are a fallback only when IDs are absent")
    func missingArtistIDs() throws {
        let favorites = HomeFavorites(artists: [ArtistID3(id: "known", name: "Beyoncé")])
        let sameNameOtherID = try album("other", artistID: "other-artist", artist: "Beyonce")
        let missingID = try album("missing", artistID: nil, artist: "Beyonce")
        #expect(HomePersonalization.relevantAdditions([sameNameOtherID, missingID], favorites: favorites, frequent: []).map(\.id) == ["missing"])
    }

    @Test("Genre shelves don't repeat albums tagged with several genres")
    func distinctGenreShelves() throws {
        let shared = try (0..<8).map { try album("shared-\($0)", artistID: "aphex") }
        let ambientOnly = try (0..<8).map { try album("ambient-\($0)", artistID: "eno") }
        let shelves = HomePersonalization.distinctGenreShelves([
            ("electronic", shared),
            ("ambient", shared + ambientOnly),
            ("Electronic", shared),
            ("experimental", shared),
        ], minimum: 6, seed: "day")
        #expect(shelves.map(\.name) == ["electronic", "ambient"])
        #expect(Set(shelves[0].albums.map(\.id)) == Set(shared.map(\.id)))
        #expect(Set(shelves[1].albums.map(\.id)) == Set(ambientOnly.map(\.id)))
    }

    @Test("A genre shelf's order is shuffled, steady for a seed")
    func genreShelfOrder() throws {
        let albums = try (0..<20).map { try album("album-\($0)", artistID: "artist") }
        let first = HomePersonalization.distinctGenreShelves([("rock", albums)], seed: "a")[0].albums.map(\.id)
        let again = HomePersonalization.distinctGenreShelves([("rock", albums)], seed: "a")[0].albums.map(\.id)
        let other = HomePersonalization.distinctGenreShelves([("rock", albums)], seed: "b")[0].albums.map(\.id)
        #expect(first == again)
        #expect(first != albums.map(\.id))
        #expect(first != other)
    }

    @Test("The earlier offline Home cache still decodes after the new shelves")
    func oldCacheRemainsReadable() throws {
        let data = Data(#"{"playlists":[],"recentlyPlayed":[],"recentlyAdded":[],"genres":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(HomeFeedSnapshot.self, from: data)
        #expect(snapshot.favorites == nil)
        #expect(snapshot.mostPlayed == nil)
    }

    @Test("Personal shelves survive serialization for an offline relaunch")
    func cacheRoundTrip() throws {
        let favorite = try album("favorite", artistID: "a")
        let source = HomeFeedSnapshot(favorites: HomeFavorites(albums: [favorite]), mostPlayed: [favorite])
        let restored = try JSONDecoder().decode(HomeFeedSnapshot.self, from: JSONEncoder().encode(source))
        #expect(restored.favorites?.albums.map(\.id) == ["favorite"])
        #expect(restored.mostPlayed?.map(\.id) == ["favorite"])
    }

    private func album(_ id: String, artistID: String?, artist: String = "Artist") throws -> AlbumID3 {
        var object: [String: Any] = ["id": id, "name": id, "artist": artist, "songCount": 1, "duration": 180]
        object["artistId"] = artistID
        return try JSONDecoder().decode(AlbumID3.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

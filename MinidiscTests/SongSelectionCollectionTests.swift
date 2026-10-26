import Foundation
import Testing
@testable import Minidisc

@Suite("Song selection collection")
@MainActor
struct SongSelectionCollectionTests {
    @Test("Filters exactly as the sheet's per-body filter did, for any query and in order")
    func matchesLegacyFilter() {
        let songs = PerformanceFixtures.songs(2_000)
        let request = SongSelectionRequest(songs: songs + songs.prefix(300))
        let collection = SongSelectionCollection(request.songs)
        #expect(collection.songs.map(\.id) == LegacyHotPaths.selectionSongs(request).map(\.id))
        for query in ["", " ", "love", "LOVE", "blue night", "bjork", "cafe", "rock n roll", "zzz", "a", "love", ""] {
            let filtered = collection.filtered(by: LibrarySearchRanking.normalized(query))
            let legacy = LegacyHotPaths.visibleSelectionSongs(request, query: query)
            #expect(filtered.songs.map(\.id) == legacy.map(\.id), "query '\(query)'")
            #expect(filtered.ids == Set(legacy.map(\.id)))
        }
    }

    @Test("Repeats keep their first position")
    func dropsRepeats() {
        let songs = PerformanceFixtures.songs(3)
        let collection = SongSelectionCollection([songs[1], songs[0], songs[1], songs[2], songs[0]])
        #expect(collection.songs.map(\.id) == [songs[1].id, songs[0].id, songs[2].id])
    }
}

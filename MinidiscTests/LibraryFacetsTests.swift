import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Library tiles: genres, track artists, composers")
struct LibraryFacetsTests {
    private let songs = [
        Song(id: "1", title: "A", artist: "Main", genre: "Rock", artistId: "main",
             genres: [ItemGenre(name: "Rock"), ItemGenre(name: "Indie")],
             artists: [ArtistID3(id: "main", name: "Main"), ArtistID3(id: "guest", name: "Guest")],
             contributors: [Contributor(role: "composer", subRole: nil, artist: ContributorArtist(id: "c1", name: "Writer", musicBrainzId: nil, sortName: nil))]),
        Song(id: "2", title: "B", artist: "Main", genre: "rock", artistId: "main", displayComposer: "Other Writer"),
        Song(id: "3", title: "C", artist: "Loose Name")
    ]

    @Test func genresMergeCaseAndMultiGenreSongs() {
        let genres = LibraryFacets.facets(.genre, in: songs)
        #expect(genres.map(\.name) == ["Indie", "Rock"])
        #expect(genres.first { $0.key == "rock" }?.songCount == 2)
    }

    @Test func trackArtistsIncludeFeaturedArtists() {
        let artists = LibraryFacets.facets(.trackArtist, in: songs)
        #expect(artists.map(\.name) == ["Guest", "Loose Name", "Main"])
        #expect(artists.first { $0.key == "main" }?.songCount == 2)
        #expect(artists.first { $0.name == "Loose Name" }?.hasArtistID == false)
    }

    @Test func composersPreferContributorCredits() {
        let composers = LibraryFacets.facets(.composer, in: songs)
        #expect(composers.map(\.name) == ["Other Writer", "Writer"])
        let writer = composers.first { $0.name == "Writer" }!
        #expect(LibraryFacets.songs(of: writer, in: songs).map(\.id) == ["1"])
    }
}

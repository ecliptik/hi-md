import Foundation
import Testing
@testable import Minidisc

// MARK: - Fixtures

/// What MusicBrainz knows in these tests: studio albums only, as `MusicBrainzClient` returns them.
private nonisolated enum MB {
    static func album(_ id: String, _ title: String, _ artist: String, _ artistID: String, _ year: Int?, votes: Int = 0) -> MusicBrainzAlbum {
        MusicBrainzAlbum(releaseGroupID: id, title: title, artistCredit: artist, artistIDs: [artistID],
                         artistNames: [artist], year: year, ratingVotes: votes)
    }

    static let prettyHateMachine = album("0000000a-0001", "Pretty Hate Machine", "Nine Inch Nails", "a-nin", 1989)
    static let softBulletin = album("0000000a-0002", "The Soft Bulletin", "The Flaming Lips", "a-lips", 1999)
    static let plasticBeach = album("0000000a-0003", "Plastic Beach", "Gorillaz", "a-gorillaz", 2010)
    static let badBrains = album("0000000a-0004", "Bad Brains", "Bad Brains", "a-badbrains", 1982)
    static let modernLovers = album("0000000a-0005", "The Modern Lovers", "The Modern Lovers", "a-modernlovers", 1976)
    static let weezerBlue = album("0000000a-0006", "Weezer", "Weezer", "a-weezer", 1994)
    static let weezerGreen = album("0000000a-0007", "Weezer", "Weezer", "a-weezer", 2001)
    static let slanted = album("0000000a-0008", "Slanted and Enchanted", "Pavement", "a-pavement", 1992)
    static let homogenic = album("0000000a-0009", "Homogenic", "Björk", "a-bjork", 1997)
    static let crookedRain = album("0000000a-0010", "Crooked Rain, Crooked Rain", "Pavement", "a-pavement", 1994)
    static let goo = album("0000000a-0011", "Goo", "Sonic Youth", "a-sonicyouth", 1990, votes: 40)
    static let daydream = album("0000000a-0012", "Daydream Nation", "Sonic Youth", "a-sonicyouth", 1988, votes: 90)
    static let sister = album("0000000a-0013", "Sister", "Sonic Youth", "a-sonicyouth", 1987, votes: 60)
    static let bee = album("0000000a-0014", "Bee Thousand", "Guided by Voices", "a-gbv", 1994, votes: 70)
    static let alien = album("0000000a-0015", "Alien Lanes", "Guided by Voices", "a-gbv", 1995, votes: 50)
    static let tvs = album("0000000a-0016", "Under the Bushes Under the Stars", "Guided by Voices", "a-gbv", 1996, votes: 20)
    static let perfectFrom = album("0000000a-0017", "Perfect From Now On", "Built to Spill", "a-bts", 1997, votes: 30)
    static let keepIt = album("0000000a-0018", "Keep It Like a Secret", "Built to Spill", "a-bts", 1999, votes: 25)
    static let collab = MusicBrainzAlbum(releaseGroupID: "0000000a-0019", title: "Shared Album", artistCredit: "Built to Spill & Someone",
                                         artistIDs: ["a-bts", "a-someone"], artistNames: ["Built to Spill", "Someone"],
                                         year: 2000, ratingVotes: 999)

    static let all = [prettyHateMachine, softBulletin, plasticBeach, badBrains, modernLovers, weezerBlue, weezerGreen,
                      slanted, homogenic, crookedRain, goo, daydream, sister, bee, alien, tvs, perfectFrom, keepIt, collab]
}

/// A MusicBrainz stand-in. Like the real search, an artist filter is fuzzy: every album with the
/// title comes back, so the pipeline has to check the credit itself.
private nonisolated struct StubMusicBrainz: MusicBrainzAlbumLookup {
    var database = MB.all
    var failing = false

    func albums(titled title: String, by artist: String?) async throws -> [MusicBrainzAlbum] {
        if failing { throw MusicBrainzError.unavailable }
        return database.filter { AIRecommendationMatcher.key($0.title) == AIRecommendationMatcher.key(title) }
    }

    func albums(byArtistMBID mbid: String) async throws -> [MusicBrainzAlbum] {
        if failing { throw MusicBrainzError.unavailable }
        return database.filter { $0.artistIDs.contains(mbid) }
    }
}

private nonisolated struct StubModel: AIRecommendationModel {
    var suggestions: [AIRecommendation] = []
    var picks: @Sendable ([AIRecommendationCandidate]) -> [AIRecommendationPick] = { _ in [] }

    func suggest(_ profile: AIListeningProfile, count: Int) async throws -> [AIRecommendation] { suggestions }

    func choose(from candidates: [AIRecommendationCandidate], profile: AIListeningProfile, count: Int) async throws -> [AIRecommendationPick] {
        picks(candidates)
    }
}

private nonisolated struct StubGraph: AIRecommendationArtistGraph {
    var top: [AIRecommendationArtist] = []
    var similar: [String: [AIRecommendationArtist]] = [:]

    func topArtists(username: String) async throws -> [AIRecommendationArtist] { top }
    func similarArtists(to mbid: String) async throws -> [AIRecommendationArtist] { similar[mbid] ?? [] }
}

private let library = AIRecommendationLibrary(
    albums: [
        .init(id: "al-slanted", name: "Slanted and Enchanted", artist: "Pavement", coverArtID: "cv-slanted"),
        .init(id: "al-phm", name: "Pretty Hate Machine", artist: "Nine Inch Nails", coverArtID: "cv-phm"),
        .init(id: "al-daydream", name: "Daydream Nation", artist: "Sonic Youth", coverArtID: nil)
    ],
    artists: [
        .init(id: "ar-pavement", name: "Pavement", mbid: "a-pavement"),
        .init(id: "ar-nin", name: "Nine Inch Nails", mbid: "a-nin"),
        .init(id: "ar-sonicyouth", name: "Sonic Youth", mbid: "a-sonicyouth"),
        .init(id: "ar-lips", name: "The Flaming Lips", mbid: "a-lips")
    ]
)

private var profile: AIListeningProfile {
    var profile = AIListeningProfile()
    profile.recentAlbums = ["Pavement – Slanted and Enchanted", "Nine Inch Nails – Pretty Hate Machine"]
    profile.topArtists = ["Pavement", "Nine Inch Nails", "Sonic Youth", "The Flaming Lips"]
    profile.playlists = ["Industrial"]
    return profile
}

private func suggestion(_ album: String, _ artist: String, _ year: Int?, _ reason: String = "A good fit.") -> AIRecommendation {
    AIRecommendation(artist: artist, album: album, year: year, reason: reason)
}

private func pipeline(_ model: StubModel, musicBrainz: StubMusicBrainz = StubMusicBrainz()) -> AIRecommendationPipeline {
    AIRecommendationPipeline(model: model, musicBrainz: musicBrainz, library: library)
}

/// The screenshot's suggestions, as the on-device model returned them.
private let screenshot: [AIRecommendation] = [
    suggestion("Head Like a Hole", "The Jesus and Mary Chain", 1994, "Its noise pop echoes your industrial playlists."),
    suggestion("16 Hours", "Boards of Canada", 1999, "Hazy electronica like Homogenic."),
    suggestion("The Soft Bulletin", "The Flaming Lips", 1998, "Lush psychedelia from The Flaming Lips, whom you collect."),
    suggestion("Bad Brains", "Big Audio Dynamite", 1989, "Matches the industrial intensity in 'Industrial'."),
    suggestion("The Modern Lovers", "The Fall", 1979, "Wiry post-punk like The Fall."),
    suggestion("Plastic Beach", "Gorillaz", 2005, "Playful, genre-hopping pop."),
    suggestion("Slanted and Enchanted", "Pavement", 1992, "The lo-fi classic you keep coming back to."),
    suggestion("Homogenic", "Björk", 1997, "Bold, orchestral electronica."),
    suggestion("Weezer", "The Shins", 1999, "Hooky indie rock.")
]

// MARK: - Free suggestions, verified

@Suite("AI recommendation verification")
struct AIRecommendationVerificationTests {
    @Test func screenshotKeepsOnlyRealAlbumsWithMusicBrainzFacts() async throws {
        let results = try await pipeline(StubModel(suggestions: screenshot)).recommend(profile)
        #expect(results.map(\.recommendation.album) == ["The Soft Bulletin", "Plastic Beach", "Slanted and Enchanted", "Homogenic"])
        #expect(results.map(\.recommendation.year) == [1999, 2010, 1992, 1997])
        #expect(results.allSatisfy { $0.recommendation.releaseGroupID != nil })
    }

    @Test func wrongArtistIsCorrectedWhenOneArtistTheListenerKnowsHasTheAlbum() async throws {
        let model = StubModel(suggestions: [
            suggestion("Pretty Hate Machine", "The Jesus and Mary Chain", 1994, "Like The Jesus and Mary Chain's noise pop.")
        ])
        let result = try #require(try await pipeline(model).recommend(profile).first)
        #expect(result.recommendation.artist == "Nine Inch Nails")
        #expect(result.recommendation.year == 1989)
        #expect(result.availability == .inLibrary(albumID: "al-phm", coverArtID: "cv-phm"))
        // The reason was about the wrong artist.
        #expect(!result.recommendation.reason.contains("Jesus"))
    }

    @Test func wrongArtistForASongIsDropped() async throws {
        // "Head Like a Hole" is a Nine Inch Nails single, not an album by anyone.
        let model = StubModel(suggestions: [suggestion("Head Like a Hole", "The Jesus and Mary Chain", 1994), suggestion("Homogenic", "Björk", 1997)])
        let results = try await pipeline(model).recommend(profile)
        #expect(results.map(\.recommendation.album) == ["Homogenic"])
    }

    @Test func albumThatDoesNotExistIsDropped() async throws {
        let model = StubModel(suggestions: [suggestion("16 Hours", "Boards of Canada", 1999), suggestion("Homogenic", "Björk", 1997)])
        let results = try await pipeline(model).recommend(profile)
        #expect(results.map(\.recommendation.album) == ["Homogenic"])
    }

    @Test func wrongYearIsCorrectedFromMusicBrainz() async throws {
        let model = StubModel(suggestions: [suggestion("The Soft Bulletin", "The Flaming Lips", 1998),
                                            suggestion("Plastic Beach", "Gorillaz", 2005)])
        let results = try await pipeline(model).recommend(profile)
        #expect(results.map(\.recommendation.year) == [1999, 2010])
        #expect(results.map(\.recommendation.releaseGroupID) == [MB.softBulletin.releaseGroupID, MB.plasticBeach.releaseGroupID])
    }

    @Test func ownedAlbumOpensInTheLibrary() async throws {
        let model = StubModel(suggestions: [suggestion("slanted & enchanted", "pavement", nil)])
        let pipeline = pipeline(model, musicBrainz: StubMusicBrainz(database: [
            MB.album("0000000a-0008", "Slanted & Enchanted", "Pavement", "a-pavement", 1992)
        ]))
        let result = try #require(try await pipeline.recommend(profile).first)
        // "&" and "and", case and spacing all match the library's "Slanted and Enchanted".
        #expect(result.availability == .inLibrary(albumID: "al-slanted", coverArtID: "cv-slanted"))
        #expect(result.recommendation.album == "Slanted & Enchanted")
    }

    @Test func ownedAlbumMatchedByNameOpensAlbum() async throws {
        let model = StubModel(suggestions: [suggestion("Slanted and Enchanted", "Pavement", 1992)])
        let result = try #require(try await pipeline(model).recommend(profile).first)
        #expect(result.availability == .inLibrary(albumID: "al-slanted", coverArtID: "cv-slanted"))
    }

    @Test(arguments: [
        ("Weezer", "The Shins"),
        ("Bad Brains", "Big Audio Dynamite"),
        ("The Modern Lovers", "The Fall")
    ])
    func titleThatIsAnArtistsNameIsDropped(album: String, artist: String) async throws {
        let model = StubModel(suggestions: [suggestion(album, artist, nil), suggestion("Homogenic", "Björk", 1997)])
        let results = try await pipeline(model).recommend(profile)
        #expect(results.map(\.recommendation.album) == ["Homogenic"])
    }

    @Test func selfTitledAlbumByTheRightArtistIsKept() async throws {
        let model = StubModel(suggestions: [suggestion("Weezer", "Weezer", 2008)])
        let result = try #require(try await pipeline(model).recommend(profile).first)
        // The original 1994 album, not a later one of the same name.
        #expect(result.recommendation.year == 1994)
        #expect(result.recommendation.releaseGroupID == MB.weezerBlue.releaseGroupID)
    }

    @Test func duplicatesAreShownOnce() async throws {
        let model = StubModel(suggestions: [suggestion("The Soft Bulletin", "The Flaming Lips", 1998),
                                            suggestion("Soft Bulletin", "Flaming Lips", 1999),
                                            suggestion("The Soft Bulletin (Deluxe Edition)", "The Flaming Lips", nil)])
        let results = try await pipeline(model).recommend(profile)
        #expect(results.count == 1)
    }

    @Test func atMostTwoOwnedAlbumsAreKept() async throws {
        let model = StubModel(suggestions: [suggestion("Slanted and Enchanted", "Pavement", nil),
                                            suggestion("Pretty Hate Machine", "Nine Inch Nails", nil),
                                            suggestion("Daydream Nation", "Sonic Youth", nil),
                                            suggestion("Homogenic", "Björk", nil)])
        let results = try await pipeline(model).recommend(profile)
        let owned = results.filter { if case .inLibrary = $0.availability { true } else { false } }
        #expect(owned.count == AIRecommendationPipeline.maxOwned)
        #expect(results.map(\.recommendation.album).contains("Homogenic"))
    }

    @Test func reasonNamingSomethingElseIsReplaced() async throws {
        let model = StubModel(suggestions: [
            suggestion("Homogenic", "Björk", 1997, "Hazy electronica like Boards of Canada."),
            suggestion("Plastic Beach", "Gorillaz", 2005, "Released in 2005, a playful record."),
            suggestion("The Soft Bulletin", "The Flaming Lips", 1998, "Lush psychedelia from The Flaming Lips, whom you collect.")
        ])
        let results = try await pipeline(model).recommend(profile)
        #expect(results[0].recommendation.reason == AIRecommendationPipeline.fallbackReason(
            album: MB.homogenic, seeds: [], availability: .missing))
        #expect(!results[1].recommendation.reason.contains("2005"))
        // A reason that sticks to the facts stays.
        #expect(results[2].recommendation.reason == "Lush psychedelia from The Flaming Lips, whom you collect.")
    }

    @Test func nothingVerifiedIsAnError() async {
        let model = StubModel(suggestions: [suggestion("16 Hours", "Boards of Canada", 1999)])
        await #expect(throws: AIRecommendationError.unverified) { try await pipeline(model).recommend(profile) }
    }

    @Test func musicBrainzOutageIsAnErrorRatherThanUncheckedAlbums() async {
        let model = StubModel(suggestions: screenshot)
        await #expect(throws: AIRecommendationError.unverified) {
            try await pipeline(model, musicBrainz: StubMusicBrainz(failing: true)).recommend(profile)
        }
    }

    @Test func slowModelTimesOut() async {
        await #expect(throws: AIRecommendationError.timedOut) {
            try await AIRecommendationPipeline.withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
                return 1
            }
        }
    }
}

// MARK: - Grounded candidates

@Suite("AI recommendation grounded candidates")
struct AIRecommendationGroundedTests {
    private let graph = StubGraph(
        top: [AIRecommendationArtist(name: "Pavement", mbid: "a-pavement")],
        similar: ["a-pavement": [
            AIRecommendationArtist(name: "Sonic Youth", mbid: "a-sonicyouth"),
            AIRecommendationArtist(name: "Guided by Voices", mbid: "a-gbv"),
            AIRecommendationArtist(name: "Built to Spill", mbid: "a-bts")
        ]]
    )

    private func grounded(_ picks: @escaping @Sendable ([AIRecommendationCandidate]) -> [AIRecommendationPick]) -> AIRecommendationPipeline {
        var pipeline = AIRecommendationPipeline(model: StubModel(picks: picks), musicBrainz: StubMusicBrainz(), library: library)
        pipeline.graph = graph
        pipeline.username = "listener"
        return pipeline
    }

    @Test func candidatesAreRealAlbumsBySimilarArtistsWithTheirSeeds() async {
        let candidates = await grounded { _ in [] }.groundedCandidates(until: .now + .seconds(5))
        #expect(!candidates.isEmpty)
        #expect(candidates.allSatisfy { $0.seeds == ["Pavement"] })
        // Seeds' own albums and collaborations aren't candidates; ids are unique.
        #expect(!candidates.contains { $0.album.artistCredit == "Pavement" })
        #expect(!candidates.contains { $0.album.releaseGroupID == MB.collab.releaseGroupID })
        #expect(Set(candidates.map(\.id)).count == candidates.count)
        // Best-known first, and at most one owned album per artist.
        let sonicYouth = candidates.filter { $0.album.artistCredit == "Sonic Youth" }.map(\.album.title)
        #expect(sonicYouth == ["Daydream Nation", "Sister", "Goo"])
    }

    @Test func idsNotOnTheListAreDropped() async throws {
        let pipeline = grounded { candidates in
            [AIRecommendationPick(id: candidates[1].id, reason: "Noisy like Pavement."),
             AIRecommendationPick(id: "c99", reason: "Not real."),
             AIRecommendationPick(id: "Homogenic", reason: "Not an id."),
             AIRecommendationPick(id: candidates[1].id, reason: "Again.")]
        }
        let candidates = await pipeline.groundedCandidates(until: .now + .seconds(5))
        let results = try await pipeline.recommend(profile)
        #expect(results.first?.recommendation.releaseGroupID == candidates[1].album.releaseGroupID)
        #expect(results.first?.recommendation.reason == "Noisy like Pavement.")
        let allowed = Set(candidates.map(\.album.releaseGroupID))
        #expect(results.allSatisfy { allowed.contains($0.recommendation.releaseGroupID ?? "") })
        #expect(!results.contains { $0.recommendation.album == "Homogenic" })
        #expect(Set(results.map(\.id)).count == results.count)
    }

    @Test func tooFewValidPicksAreFilledFromTheList() async throws {
        let results = try await grounded { _ in [AIRecommendationPick(id: "c42", reason: "?")] }.recommend(profile)
        #expect(results.count >= AIRecommendationPipeline.minimumShown)
        #expect(results.allSatisfy { $0.recommendation.reason.contains("Pavement") })
    }

    @Test func reasonNamingAnArtistNotGivenIsReplaced() async throws {
        let pipeline = grounded { candidates in
            [AIRecommendationPick(id: candidates[0].id, reason: "Fans of The Fall and Big Audio Dynamite will love it.")]
        }
        let first = try #require(try await pipeline.recommend(profile).first)
        #expect(first.recommendation.reason == String(localized: "Similar to \("Pavement"), which you listen to."))
    }

    @Test func ownedCandidateOpensAlbum() async throws {
        let pipeline = grounded { candidates in
            candidates.filter { $0.album.title == "Daydream Nation" }.map { AIRecommendationPick(id: $0.id, reason: "") }
        }
        let results = try await pipeline.recommend(profile)
        let daydream = try #require(results.first { $0.recommendation.album == "Daydream Nation" })
        #expect(daydream.availability == .inLibrary(albumID: "al-daydream", coverArtID: nil))
    }

    @Test func withoutEnoughCandidatesSuggestionsAreVerifiedInstead() async throws {
        var pipeline = AIRecommendationPipeline(
            model: StubModel(suggestions: [suggestion("Homogenic", "Björk", 1990)]), musicBrainz: StubMusicBrainz(), library: library
        )
        pipeline.graph = StubGraph()
        let results = try await pipeline.recommend(profile)
        #expect(results.map(\.recommendation.year) == [1997])
    }
}

// MARK: - Reasons

@Suite("AI recommendation reason check")
struct AIRecommendationReasonCheckTests {
    private let allowed = ["Slanted and Enchanted", "Pavement", "Sonic Youth"]
    private let known = ["Pavement", "Sonic Youth", "The Fall", "Björk", "Boards of Canada"]

    private func check(_ reason: String, allowed: [String]? = nil, year: Int? = 1992) -> Bool {
        AIRecommendationReasonCheck.isGrounded(reason, allowed: allowed ?? self.allowed, known: known, year: year)
    }

    @Test func reasonsAboutTheGivenFactsPass() {
        #expect(check("Pavement's Slanted and Enchanted shares the lo-fi spirit of Sonic Youth."))
        #expect(check("Like Slanted and Enchanted, it's scrappy and melodic."))
        #expect(check("Fans of Pavement and Sonic Youth will feel at home."))
        #expect(check("A 1992 lo-fi landmark."))
        #expect(check("Low-key and noisy, in the best way."))
    }

    @Test func otherArtistsAreCaught() {
        #expect(!check("The Fall's angular post-punk lives here."))
        #expect(!check("Recalls The Fall at their most wiry."))
        #expect(!check("Hazy like Boards of Canada."))
        #expect(!check("As adventurous as Björk."))
        #expect(!check("Echoes Big Audio Dynamite's dance-rock."))
    }

    @Test func quotedNamesMustBeGiven() {
        #expect(!check("Matches the intensity in 'Industrial'."))
        #expect(check("Matches the intensity in 'Industrial'.", allowed: allowed + ["Industrial"]))
    }

    @Test func yearsMustBeTheAlbums() {
        #expect(!check("This 1994 classic still sounds fresh."))
        #expect(!check("A 1992 classic.", year: nil))
        #expect(check("Peak 1990s indie rock."))
    }

    @Test func emptyReasonFails() {
        #expect(!check("   "))
    }
}

// MARK: - Reasons stay on the pick and its seed

/// The screenshots' reasons: real albums, but reasons that wove in the listener's playlists and
/// other albums. Only the pick's facts and the artist it was found through may be named.
@Suite("AI recommendation reasons name only the pick and its seed")
struct AIRecommendationSeedReasonTests {
    private let listener: AIListeningProfile = {
        var profile = AIListeningProfile()
        profile.recentAlbums = ["Ozma – Spending Time on the Borderline", "Various Artists – Garden State",
                                "Arcade Fire – Funeral"]
        profile.topArtists = ["Ozma", "The National", "Pavement"]
        profile.playlists = ["City Pop", "Garden State", "Chill"]
        return profile
    }()
    private let known = ["Ozma", "The National", "Pavement", "Arcade Fire", "Neutral Milk Hotel"]

    /// What `choose` checks a grounded pick's reason against.
    private func pick(_ reason: String, album: String, artist: String, seeds: [String]) -> Bool {
        AIRecommendationReasonCheck.isGrounded(
            reason, allowed: [album, artist] + seeds, known: known, denied: listener.deniedNames, year: nil
        )
    }

    @Test func playlistAndAlbumNamesFromTheProfileAreDenied() {
        #expect(Set(listener.deniedNames) == ["City Pop", "Garden State", "Chill", "Spending Time on the Borderline", "Funeral"])
    }

    @Test func funeralWithCityPopVibesIsRejected() {
        #expect(!pick("Combines the anthemic energy of City Pop vibes.", album: "Funeral", artist: "Arcade Fire", seeds: ["The National"]))
        // Opening the sentence doesn't hide a playlist's name.
        #expect(!pick("City Pop vibes meet Arcade Fire's anthems.", album: "Funeral", artist: "Arcade Fire", seeds: ["The National"]))
    }

    @Test func aeroplaneWithOzmasAlbumIsRejected() {
        #expect(!pick("Captures the surrealism in Ozma's Spending Time On The Border Line.",
                      album: "In the Aeroplane Over the Sea", artist: "Neutral Milk Hotel", seeds: ["Ozma"]))
        #expect(!pick("Captures the surrealism of Spending Time on the Borderline.",
                      album: "In the Aeroplane Over the Sea", artist: "Neutral Milk Hotel", seeds: ["Ozma"]))
    }

    @Test func gardenStateTracksAreRejected() {
        #expect(!pick("Shares the introspective edge in Garden State tracks.", album: "Boxer", artist: "The National", seeds: ["Arcade Fire"]))
        #expect(!pick("Shares the introspective edge of your garden state playlist.", album: "Boxer", artist: "The National", seeds: ["Arcade Fire"]))
    }

    @Test func anArtistThatIsntTheSeedIsRejected() {
        // Ozma is the listener's, but this pick came from The National.
        #expect(!pick("As fuzzy and sincere as Ozma.", album: "Funeral", artist: "Arcade Fire", seeds: ["The National"]))
    }

    @Test func reasonsAboutTheSoundNextToTheSeedPass() {
        #expect(pick("Arcade Fire's Funeral swells with the same anthemic yearning as The National.",
                     album: "Funeral", artist: "Arcade Fire", seeds: ["The National"]))
        #expect(pick("Like Ozma, it's fuzzy, sincere and full of horns.",
                     album: "In the Aeroplane Over the Sea", artist: "Neutral Milk Hotel", seeds: ["Ozma"]))
        // The pick's own title may be in the profile; it is still the pick's.
        #expect(pick("Funeral is as anthemic as The National at their biggest.",
                     album: "Funeral", artist: "Arcade Fire", seeds: ["The National"]))
        // An ordinary word that happens to be a playlist's name, uncapitalised.
        #expect(pick("Hushed and chill, like Arcade Fire at their quietest.", album: "Boxer", artist: "The National", seeds: ["Arcade Fire"]))
    }

    @Test func aFreeSuggestionMayNameTheListenersArtistsButNotTheirPlaylists() {
        func free(_ reason: String) -> Bool {
            AIRecommendationReasonCheck.isGrounded(
                reason, allowed: ["Funeral", "Arcade Fire"] + listener.artistNames, known: known,
                denied: listener.deniedNames, year: nil
            )
        }
        #expect(free("As cathartic as The National."))
        #expect(!free("Echoes your Garden State playlist."))
        #expect(!free("Pure City Pop energy."))
    }

    @Test func rejectedPicksGetTheSeedFallback() async throws {
        var withPlaylists = profile
        withPlaylists.playlists = ["City Pop", "Garden State"]
        var pipeline = AIRecommendationPipeline(
            model: StubModel(picks: { candidates in
                [AIRecommendationPick(id: candidates[0].id, reason: "Combines the anthemic energy of City Pop vibes."),
                 AIRecommendationPick(id: candidates[1].id, reason: "Shares the introspective edge in Garden State tracks."),
                 AIRecommendationPick(id: candidates[2].id, reason: "Scrappy and noisy, like Pavement.")]
            }),
            musicBrainz: StubMusicBrainz(), library: library
        )
        pipeline.graph = StubGraph(
            top: [AIRecommendationArtist(name: "Pavement", mbid: "a-pavement")],
            similar: ["a-pavement": [
                AIRecommendationArtist(name: "Sonic Youth", mbid: "a-sonicyouth"),
                AIRecommendationArtist(name: "Guided by Voices", mbid: "a-gbv"),
                AIRecommendationArtist(name: "Built to Spill", mbid: "a-bts")
            ]]
        )
        pipeline.username = "listener"
        let results = try await pipeline.recommend(withPlaylists)
        let fallback = String(localized: "Similar to \("Pavement"), which you listen to.")
        #expect(results[0].recommendation.reason == fallback)
        #expect(results[1].recommendation.reason == fallback)
        #expect(results[2].recommendation.reason == "Scrappy and noisy, like Pavement.")
    }

    @Test func thePromptsAskForTheSoundNextToTheSeedOnly() {
        let candidate = AIRecommendationCandidate(id: "c1", album: MB.goo, seeds: ["Pavement"])
        let prompt = listener.choicePrompt([candidate], count: 5)
        #expect(prompt.contains("similar to Pavement"))
        #expect(prompt.contains("Don't mention playlists, songs or"))
        #expect(!prompt.contains("City Pop"), "the choice prompt never lists playlists")
        #expect(AIListeningProfile.choiceSystemPrompt.contains("never a playlist, a"))
        #expect(AIListeningProfile.systemPrompt.contains("Never mention their playlists,"))
    }
}

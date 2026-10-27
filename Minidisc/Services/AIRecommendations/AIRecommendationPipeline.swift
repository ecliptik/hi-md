import Foundation
import OSLog

// The model's answers are candidates, never facts. Albums come from MusicBrainz (title, artist
// and year included), ownership from the library index, and a reason is kept only when it names
// nothing the model wasn't given.

/// An artist with its MusicBrainz id: one the listener plays, or one similar to them.
nonisolated struct AIRecommendationArtist: Sendable, Hashable {
    let name: String
    let mbid: String
}

/// Where grounded candidates come from: the listener's top artists and artists similar to them.
nonisolated protocol AIRecommendationArtistGraph: Sendable {
    func topArtists(username: String) async throws -> [AIRecommendationArtist]
    func similarArtists(to mbid: String) async throws -> [AIRecommendationArtist]
}

/// ListenBrainz statistics and its similar-artists data.
nonisolated struct ListenBrainzArtistGraph: AIRecommendationArtistGraph {
    let client: ListenBrainzClient

    func topArtists(username: String) async throws -> [AIRecommendationArtist] {
        try await client.topArtists(forUser: username).compactMap { dto in
            dto.mbid.map { AIRecommendationArtist(name: dto.name, mbid: $0) }
        }
    }

    func similarArtists(to mbid: String) async throws -> [AIRecommendationArtist] {
        try await client.similarArtists(mbid: mbid).map { AIRecommendationArtist(name: $0.name, mbid: $0.artistMbid) }
    }
}

/// A real album the model may choose, with the listener's artists that led to it.
nonisolated struct AIRecommendationCandidate: Sendable, Hashable {
    let id: String
    let album: MusicBrainzAlbum
    /// Names of the listener's artists it is similar to.
    let seeds: [String]

    var promptLine: String {
        let year = album.year.map { " (\(String($0)))" } ?? ""
        let similar = seeds.isEmpty ? "" : "; similar to \(seeds.joined(separator: ", "))"
        return "- \(id): \(album.title) — \(album.artistCredit)\(year)\(similar)"
    }
}

/// The model's choice of one candidate, by id.
nonisolated struct AIRecommendationPick: Sendable, Hashable, Decodable {
    let id: String
    let reason: String

    init(id: String, reason: String) {
        self.id = id
        self.reason = reason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, reason }
}

/// Apple Intelligence or a cloud provider.
nonisolated protocol AIRecommendationModel: Sendable {
    /// Free suggestions from the listening profile, verified afterwards.
    func suggest(_ profile: AIListeningProfile, count: Int) async throws -> [AIRecommendation]
    /// Picks from a list of real albums, by candidate id.
    func choose(from candidates: [AIRecommendationCandidate], profile: AIListeningProfile, count: Int) async throws -> [AIRecommendationPick]
}

/// The library as the recommendations see it: enough to tell owned albums and artists apart.
nonisolated struct AIRecommendationLibrary: Sendable {
    nonisolated struct Album: Sendable, Hashable {
        let id: String
        let name: String
        let artist: String
        var coverArtID: String?
    }

    nonisolated struct Artist: Sendable, Hashable {
        let id: String
        let name: String
        var mbid: String?
    }

    let albums: [Album]
    let artists: [Artist]
    private let albumsByKey: [String: Album]
    private let artistsByKey: [String: Artist]
    private let artistsByMBID: [String: Artist]

    init(albums: [Album] = [], artists: [Artist] = []) {
        self.albums = albums
        self.artists = artists
        var byKey: [String: Album] = [:]
        for album in albums {
            let key = Self.albumKey(artist: album.artist, title: album.name)
            if byKey[key] == nil { byKey[key] = album }
        }
        albumsByKey = byKey
        artistsByKey = Dictionary(artists.map { (AIRecommendationMatcher.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        artistsByMBID = Dictionary(artists.compactMap { artist in artist.mbid.map { ($0.lowercased(), artist) } },
                                   uniquingKeysWith: { first, _ in first })
    }

    static func albumKey(artist: String, title: String) -> String {
        AIRecommendationMatcher.key(artist) + "|" + AIRecommendationMatcher.key(title)
    }

    var artistNameKeys: Set<String> { Set(artistsByKey.keys) }

    func availability(of album: MusicBrainzAlbum) -> AIRecommendationAvailability {
        let names = [album.artistCredit] + album.artistNames
        for name in names {
            if let owned = albumsByKey[Self.albumKey(artist: name, title: album.title)] {
                return .inLibrary(albumID: owned.id, coverArtID: owned.coverArtID)
            }
        }
        if let artist = album.artistIDs.lazy.compactMap({ artistsByMBID[$0.lowercased()] }).first
            ?? names.lazy.compactMap({ artistsByKey[AIRecommendationMatcher.key($0)] }).first {
            return .artistInLibrary(artistID: artist.id)
        }
        return .missing
    }

    func owns(_ album: MusicBrainzAlbum) -> Bool {
        if case .inLibrary = availability(of: album) { true } else { false }
    }
}

/// Turns the listening profile into verified album recommendations.
///
/// 1. Candidates: with ListenBrainz connected, real albums (MusicBrainz release groups) by
///    artists similar to the listener's own; the model only chooses among them, by id. Otherwise
///    the model suggests freely and each suggestion is looked up.
/// 2. Verification: title, artist and year always come from MusicBrainz. Suggestions that don't
///    resolve, or whose title is really an artist's name, are dropped.
/// 3. Library match: owned albums open in the library; at most `maxOwned` are kept.
/// 4. Reasons: kept only when they name nothing but the album, its artist and the listener's
///    artists it was found through, never a playlist or another album; otherwise replaced by a
///    factual one.
nonisolated struct AIRecommendationPipeline: Sendable {
    /// Asked of the model; more than are shown, since some won't verify.
    static let requested = 12
    static let shown = 8
    /// Below this many grounded picks, the rest of the candidate list fills in.
    static let minimumShown = 6
    /// The feature is for finding new albums, so only a couple the listener owns stay in.
    static let maxOwned = 2
    static let seedCount = 5
    static let similarPerSeed = 8
    static let candidateArtists = 8
    static let unownedPerArtist = 3

    let model: any AIRecommendationModel
    let musicBrainz: any MusicBrainzAlbumLookup
    let library: AIRecommendationLibrary
    /// Set when ListenBrainz is connected.
    var graph: (any AIRecommendationArtistGraph)?
    var username: String?
    /// The listener's artists from the library, most played first, for when ListenBrainz has no
    /// statistics yet.
    var librarySeeds: [AIRecommendationArtist] = []
    /// For gathering grounded candidates (ListenBrainz and MusicBrainz, one request a second).
    var candidateBudget: Duration = .seconds(20)
    /// For checking free suggestions against MusicBrainz.
    var verificationBudget: Duration = .seconds(30)
    var modelTimeout: Duration = .seconds(90)

    init(model: any AIRecommendationModel, musicBrainz: any MusicBrainzAlbumLookup, library: AIRecommendationLibrary) {
        self.model = model
        self.musicBrainz = musicBrainz
        self.library = library
    }

    func recommend(_ profile: AIListeningProfile) async throws -> [AIRecommendationResult] {
        if graph != nil {
            let candidates = await groundedCandidates(until: .now + candidateBudget)
            if candidates.count >= Self.minimumShown {
                return try await choose(from: candidates, profile: profile)
            }
            Logger.ui.info("AI recommendations: \(candidates.count) grounded candidates, checking free suggestions instead")
        }
        return try await verifiedSuggestions(profile)
    }

    // MARK: - Grounded candidates

    func groundedCandidates(until deadline: ContinuousClock.Instant) async -> [AIRecommendationCandidate] {
        guard let graph else { return [] }
        var seeds: [AIRecommendationArtist] = []
        if let username, let top = try? await graph.topArtists(username: username) {
            seeds += top.prefix(Self.seedCount - 1)
        }
        seeds += librarySeeds
        var seenSeeds = Set<String>()
        seeds = seeds.filter { seenSeeds.insert($0.mbid.lowercased()).inserted }.prefix(Self.seedCount).map { $0 }
        guard !seeds.isEmpty else { return [] }

        // Similar artists, scored by how many seeds lead to them and how closely.
        struct Scored { let artist: AIRecommendationArtist; var score: Int; var seeds: [String] }
        var scored: [String: Scored] = [:]
        var order: [String] = []
        for seed in seeds {
            guard ContinuousClock.now < deadline else { break }
            guard let similar = try? await graph.similarArtists(to: seed.mbid) else { continue }
            for (rank, artist) in similar.prefix(Self.similarPerSeed).enumerated() {
                let id = artist.mbid.lowercased()
                guard !seenSeeds.contains(id) else { continue }
                if scored[id] == nil {
                    scored[id] = Scored(artist: artist, score: 0, seeds: [])
                    order.append(id)
                }
                scored[id]?.score += Self.similarPerSeed - rank
                if scored[id]?.seeds.contains(seed.name) == false { scored[id]?.seeds.append(seed.name) }
            }
        }
        let ranked = order.compactMap { scored[$0] }.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(Self.candidateArtists).map(\.element)

        var candidates: [AIRecommendationCandidate] = []
        var seenAlbums = Set<String>()
        for entry in ranked {
            guard ContinuousClock.now < deadline else { break }
            guard let albums = try? await musicBrainz.albums(byArtistMBID: entry.artist.mbid) else { continue }
            // Exact artist credit: the artist alone, not a collaboration.
            let own = albums
                .filter { $0.artistIDs.map { $0.lowercased() } == [entry.artist.mbid.lowercased()] }
                .sorted { lhs, rhs in
                    lhs.ratingVotes != rhs.ratingVotes ? lhs.ratingVotes > rhs.ratingVotes : (lhs.year ?? .max) < (rhs.year ?? .max)
                }
            var unowned = 0
            var owned = 0
            for album in own {
                guard seenAlbums.insert(album.releaseGroupID).inserted,
                      seenAlbums.insert(AIRecommendationLibrary.albumKey(artist: album.artistCredit, title: album.title)).inserted
                else { continue }
                if library.owns(album) {
                    guard owned < 1 else { continue }
                    owned += 1
                } else {
                    guard unowned < Self.unownedPerArtist else { continue }
                    unowned += 1
                }
                candidates.append(AIRecommendationCandidate(id: "c\(candidates.count + 1)", album: album, seeds: entry.seeds))
                if unowned >= Self.unownedPerArtist, owned >= 1 { break }
            }
        }
        return candidates
    }

    /// The model chooses by id; ids not on the list are dropped.
    func choose(from candidates: [AIRecommendationCandidate], profile: AIListeningProfile) async throws -> [AIRecommendationResult] {
        let model = self.model
        let picks = try await Self.withTimeout(modelTimeout) {
            try await model.choose(from: candidates, profile: profile, count: Self.requested)
        }
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = knownNames(profile: profile, extra: candidates.flatMap { [$0.album.artistCredit] + $0.album.artistNames })
        var chosen: [(candidate: AIRecommendationCandidate, reason: String?)] = []
        var seen = Set<String>()
        for pick in picks {
            let id = pick.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let candidate = byID[id], seen.insert(candidate.id).inserted else {
                Logger.ui.info("AI recommendations: dropped a pick that isn't on the candidate list")
                continue
            }
            // Only the album's own facts and the listener's artists it was found through.
            let allowed = Self.facts(of: candidate.album) + candidate.seeds
            let grounded = AIRecommendationReasonCheck.isGrounded(
                pick.reason, allowed: allowed, known: known, denied: profile.deniedNames, year: candidate.album.year
            )
            chosen.append((candidate, grounded ? pick.reason : nil))
        }
        // Too few valid picks: the rest of the list, one album per artist first.
        if chosen.count < Self.minimumShown {
            var usedArtists = Set(chosen.map { AIRecommendationMatcher.key($0.candidate.album.artistCredit) })
            for pass in 0..<2 {
                for candidate in candidates where !seen.contains(candidate.id) {
                    let artist = AIRecommendationMatcher.key(candidate.album.artistCredit)
                    if pass == 0, usedArtists.contains(artist) { continue }
                    seen.insert(candidate.id)
                    usedArtists.insert(artist)
                    chosen.append((candidate, nil))
                }
            }
        }
        var results: [AIRecommendationResult] = []
        var owned = 0
        for (candidate, reason) in chosen {
            guard results.count < Self.shown else { break }
            let availability = library.availability(of: candidate.album)
            if case .inLibrary = availability {
                guard owned < Self.maxOwned else { continue }
                owned += 1
            }
            results.append(Self.result(candidate.album, reason: reason, seeds: candidate.seeds, availability: availability))
        }
        return results
    }

    // MARK: - Free suggestions, verified

    func verifiedSuggestions(_ profile: AIListeningProfile) async throws -> [AIRecommendationResult] {
        let model = self.model
        let suggestions = try await Self.withTimeout(modelTimeout) {
            try await model.suggest(profile, count: Self.requested)
        }
        let deadline = ContinuousClock.now + verificationBudget
        let listenerArtists = library.artistNameKeys.union(profile.artistNames.map(AIRecommendationMatcher.key))
        let known = knownNames(profile: profile, extra: suggestions.map(\.artist))
        var results: [AIRecommendationResult] = []
        var seen = Set<String>()
        var owned = 0
        var lookupFailures = 0
        for suggestion in suggestions {
            guard results.count < Self.shown, ContinuousClock.now < deadline else { break }
            let verified: Verified?
            do {
                verified = try await verify(suggestion, listenerArtists: listenerArtists)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lookupFailures += 1
                continue
            }
            guard let verified else {
                Logger.ui.info("AI recommendations: dropped a suggestion MusicBrainz doesn't confirm")
                continue
            }
            let album = verified.album
            guard seen.insert(album.releaseGroupID).inserted,
                  seen.insert(AIRecommendationLibrary.albumKey(artist: album.artistCredit, title: album.title)).inserted
            else { continue }
            let availability = library.availability(of: album)
            if case .inLibrary = availability {
                guard owned < Self.maxOwned else { continue }
                owned += 1
            }
            // A corrected artist means the reason was written about the wrong one. A free
            // suggestion wasn't found through one artist, so the listener's artists stand in for
            // its seeds; their albums and playlists don't.
            let grounded = !verified.corrected && AIRecommendationReasonCheck.isGrounded(
                suggestion.reason, allowed: Self.facts(of: album) + profile.artistNames, known: known,
                denied: profile.deniedNames, year: album.year
            )
            results.append(Self.result(album, reason: grounded ? suggestion.reason : nil, seeds: [], availability: availability))
        }
        if lookupFailures > 0 {
            Logger.ui.notice("AI recommendations: \(lookupFailures) MusicBrainz lookups failed")
        }
        guard !results.isEmpty else { throw AIRecommendationError.unverified }
        return results
    }

    struct Verified: Sendable, Equatable {
        let album: MusicBrainzAlbum
        /// The model credited the wrong artist, and MusicBrainz had exactly one right one.
        let corrected: Bool
    }

    /// Looks the suggestion up by title and artist. When the artist is wrong, it is corrected
    /// only if exactly one artist has a studio album of that title, that artist is one the
    /// listener knows, and the title isn't itself an artist's name ("Weezer" by The Shins).
    func verify(_ suggestion: AIRecommendation, listenerArtists: Set<String>) async throws -> Verified? {
        let titleKey = AIRecommendationMatcher.key(suggestion.album)
        let artistKey = AIRecommendationMatcher.key(suggestion.artist)
        guard !titleKey.isEmpty, !artistKey.isEmpty else { return nil }

        let exact = try await musicBrainz.albums(titled: suggestion.album, by: suggestion.artist).filter {
            AIRecommendationMatcher.key($0.title) == titleKey && Self.isCredited($0, artistKey: artistKey)
        }
        if let album = Self.earliest(exact) { return Verified(album: album, corrected: false) }

        // The title names an artist the listener has, so it's an artist the model confused.
        guard !listenerArtists.contains(titleKey) else { return nil }
        let byTitle = try await musicBrainz.albums(titled: suggestion.album, by: nil).filter {
            AIRecommendationMatcher.key($0.title) == titleKey
        }
        guard !byTitle.contains(where: Self.isSelfTitled) else { return nil }
        let artists = Set(byTitle.map { AIRecommendationMatcher.key($0.artistCredit) })
        guard artists.count == 1, let artist = artists.first, listenerArtists.contains(artist),
              let album = Self.earliest(byTitle) else { return nil }
        return Verified(album: album, corrected: true)
    }

    // MARK: - Helpers

    private static func isCredited(_ album: MusicBrainzAlbum, artistKey: String) -> Bool {
        AIRecommendationMatcher.key(album.artistCredit) == artistKey
            || album.artistNames.contains { AIRecommendationMatcher.key($0) == artistKey }
    }

    private static func isSelfTitled(_ album: MusicBrainzAlbum) -> Bool {
        let title = AIRecommendationMatcher.key(album.title)
        return title == AIRecommendationMatcher.key(album.artistCredit)
            || album.artistNames.contains { AIRecommendationMatcher.key($0) == title }
    }

    /// The original release among same-titled release groups.
    private static func earliest(_ albums: [MusicBrainzAlbum]) -> MusicBrainzAlbum? {
        albums.min { lhs, rhs in
            lhs.year != rhs.year ? (lhs.year ?? .max) < (rhs.year ?? .max) : lhs.ratingVotes > rhs.ratingVotes
        }
    }

    private static func facts(of album: MusicBrainzAlbum) -> [String] {
        [album.title, album.artistCredit] + album.artistNames
    }

    /// Artist names a reason could wrongly mention: the library's, the profile's and the model's.
    private func knownNames(profile: AIListeningProfile, extra: [String]) -> [String] {
        library.artists.map(\.name) + profile.artistNames + extra
    }

    static func result(
        _ album: MusicBrainzAlbum, reason: String?, seeds: [String], availability: AIRecommendationAvailability
    ) -> AIRecommendationResult {
        let text = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recommendation = AIRecommendation(
            artist: album.artistCredit, album: album.title, year: album.year,
            reason: text?.isEmpty == false ? text! : fallbackReason(album: album, seeds: seeds, availability: availability),
            releaseGroupID: album.releaseGroupID
        )
        return AIRecommendationResult(recommendation: recommendation, availability: availability)
    }

    /// Said instead of a reason that named something it shouldn't, built only from known facts.
    static func fallbackReason(album: MusicBrainzAlbum, seeds: [String], availability: AIRecommendationAvailability) -> String {
        if !seeds.isEmpty {
            let names = Array(seeds.prefix(2)).formatted(.list(type: .and))
            return String(localized: "Similar to \(names), which you listen to.")
        }
        if case .artistInLibrary = availability {
            return String(localized: "You already have other albums by \(album.artistCredit).")
        }
        return String(localized: "Picked from your listening.")
    }

    static func withTimeout<T: Sendable>(
        _ duration: Duration, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw AIRecommendationError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AIRecommendationError.timedOut }
            return first
        }
    }
}

extension AIListeningProfile {
    /// Artist names only.
    nonisolated var artistNames: [String] {
        let albumArtists = (recentAlbums + favoriteAlbums).compactMap { $0.components(separatedBy: " – ").first }
        return topArtists + albumArtists.filter { $0 != "Unknown" }
    }

    /// Names a reason must never mention: the listener's playlists ("City Pop", "Garden State")
    /// and the titles of the albums in the profile. They help the model choose, but a reason that
    /// weaves them in links the pick to something it has nothing to do with. The pick's own title
    /// is still allowed, as an allowed name always wins.
    nonisolated var deniedNames: [String] {
        let albumTitles = (recentAlbums + favoriteAlbums).compactMap { entry -> String? in
            let parts = entry.components(separatedBy: " – ")
            return parts.count > 1 ? parts.dropFirst().joined(separator: " – ") : nil
        }
        return playlists + albumTitles
    }
}

/// Decides whether a model-written reason sticks to the facts it was given.
///
/// The allowed names are the pick's own facts (title, artist) and the listener's artists it was
/// found through. A reason is rejected when it quotes something not among them, names an artist
/// (from the library, the profile or the model's other answers) that isn't one of them, mentions a
/// denied name (the listener's playlists, the albums in their profile), strings together a
/// capitalised name that isn't one of them ("The Fall", "City Pop", "Spending Time on the
/// Borderline"), or gives a year other than the album's.
nonisolated enum AIRecommendationReasonCheck {
    private static let connectors: Set<String> = ["of", "the", "and", "&", "a", "an", "in", "on", "de", "la", "le", "du", "des", "van", "von", "y"]

    static func isGrounded(_ reason: String, allowed: [String], known: [String], denied: [String] = [], year: Int?) -> Bool {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let allowedKeys = allowed.map { AIRecommendationMatcher.key(stripPossessives($0)) }
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }

        // Playlist and album names from the profile, unless they are the pick's own facts.
        for name in Set(denied) where name.count >= 3 && !covered(name, by: allowedKeys) {
            if mentions(text, name) { return false }
        }

        // Years must be the album's.
        for match in text.matches(of: /\b(19|20)\d{2}\b/) {
            guard let year, Int(text[match.range]) == year else { return false }
        }

        // Quoted titles and names.
        for match in text.matches(of: /(?:^|[\s(])['‘"“«「]([^'’"”»」]+)['’"”»」]/) {
            guard covered(String(match.output.1), by: allowedKeys) else { return false }
        }

        // Artist names the reason could mention by mistake.
        for name in Set(known) where name.count >= 3 && !covered(name, by: allowedKeys) {
            if mentions(text, name) { return false }
        }

        // Capitalised names: "The Fall", "Big Audio Dynamite".
        for run in capitalizedRuns(text) where !covered(run.words.joined(separator: " "), by: allowedKeys) {
            // The first word may just start the sentence ("Like Slanted and Enchanted…"), unless
            // it's an article, which belongs to the name ("The Fall").
            guard run.atSentenceStart, let first = run.words.first, !connectors.contains(first.lowercased()) else { return false }
            let rest = Array(run.words.dropFirst().drop { connectors.contains($0.lowercased()) })
            if rest.filter(isCapitalized).count >= 2, !covered(rest.joined(separator: " "), by: allowedKeys) {
                return false
            }
        }
        return true
    }

    /// Whether the allowed names account for all of `text`, give or take a possessive "s".
    static func covered(_ text: String, by allowedKeys: [String]) -> Bool {
        var residue = AIRecommendationMatcher.key(stripPossessives(text))
        guard !residue.isEmpty else { return true }
        for key in allowedKeys where residue.contains(key) {
            residue = residue.replacingOccurrences(of: key, with: "")
        }
        // Connecting words left between two allowed names ("Pavement and Sonic Youth").
        for word in connectors.map({ AIRecommendationMatcher.key($0) }) where residue == word { return true }
        return residue.count <= 1
    }

    /// A whole-word mention. One-word names must match case, so "low-key" isn't the band Low.
    private static func mentions(_ text: String, _ name: String) -> Bool {
        let variants = name.lowercased().hasPrefix("the ") ? [name, String(name.dropFirst(4))] : [name]
        for variant in variants where variant.count >= 3 {
            let singleWord = !variant.contains(" ")
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: variant, options: singleWord ? [.diacriticInsensitive] : [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                let isWord = !(before?.isLetter ?? false) && !(before?.isNumber ?? false)
                    && !(after?.isLetter ?? false) && !(after?.isNumber ?? false)
                // A one-word name opening the sentence may be an ordinary word ("Low-key").
                let opensSentence = before == nil || text[..<range.lowerBound].trimmingCharacters(in: .whitespaces).last.map { ".!?".contains($0) } == true
                if isWord, !(singleWord && opensSentence) { return true }
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return false
    }

    struct Run: Equatable {
        let words: [String]
        let atSentenceStart: Bool
    }

    /// Runs of two or more capitalised words, allowing "of", "the", "and"… between them.
    static func capitalizedRuns(_ text: String) -> [Run] {
        var runs: [Run] = []
        var current: [String] = []
        var currentStartsSentence = false
        var sentenceStart = true
        func flush() {
            while let last = current.last, connectors.contains(last.lowercased()) { current.removeLast() }
            if current.filter(isCapitalized).count >= 2 { runs.append(Run(words: current, atSentenceStart: currentStartsSentence)) }
            current = []
        }
        for token in text.split(whereSeparator: \.isWhitespace) {
            let raw = String(token)
            let word = stripPossessives(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'‘’“”«»「」()[]")
                .union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "&"))))
            let endsClause = raw.last.map { ",.;:!?)\"”’»」".contains($0) } ?? false
            let endsSentence = raw.last.map { ".!?".contains($0) } ?? false
            let opensQuote = raw.first.map { "\"'‘“«「(".contains($0) } ?? false
            if opensQuote { flush() }
            if !word.isEmpty, isCapitalized(word) {
                if current.isEmpty { currentStartsSentence = sentenceStart }
                current.append(word)
            } else if !current.isEmpty, connectors.contains(word.lowercased()) {
                current.append(word)
            } else {
                flush()
            }
            if endsClause { flush() }
            sentenceStart = endsSentence
        }
        flush()
        return runs
    }

    private static func isCapitalized(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        return first.isUppercase
    }

    private static func stripPossessives(_ text: String) -> String {
        text.replacing(/['’]s\b/, with: "")
    }
}

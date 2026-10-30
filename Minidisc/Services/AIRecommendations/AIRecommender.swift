import Foundation
import FoundationModels
import Observation
import OSLog
import SwiftSonic

/// Settings > Integrations > AI Recommendations. API keys live in the keychain; the rest,
/// including which providers the user has been told about, in defaults.
@Observable
@MainActor
final class AIRecommendationSettings {
    private enum Key {
        static let provider = "ai-recommendations.provider"
        static let anthropicModel = "ai-recommendations.anthropicModel"
        static let openAIModel = "ai-recommendations.openAIModel"
        static let sharingAcknowledged = "ai-recommendations.sharingAcknowledged"
        static let playlistSharingAcknowledged = "ai-playlists.sharingAcknowledged"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: any KeychainServiceProtocol
    @ObservationIgnored private var pendingKeySave: Task<Void, Never>?

    var provider: AIRecommendationProvider { didSet { defaults.set(provider.rawValue, forKey: Key.provider) } }
    /// What the user typed. Empty means the provider's default model.
    var anthropicModel: String { didSet { defaults.set(anthropicModel, forKey: Key.anthropicModel) } }
    var openAIModel: String { didSet { defaults.set(openAIModel, forKey: Key.openAIModel) } }
    /// Cloud providers the user has seen the what-is-sent note for.
    private(set) var sharingAcknowledged: Set<AIRecommendationProvider> {
        didSet { defaults.set(sharingAcknowledged.map(\.rawValue).sorted(), forKey: Key.sharingAcknowledged) }
    }
    /// Cloud providers the user has agreed may receive song names for AI playlists, which is more
    /// than recommendations send, so it's asked separately.
    private(set) var playlistSharingAcknowledged: Set<AIRecommendationProvider> {
        didSet { defaults.set(playlistSharingAcknowledged.map(\.rawValue).sorted(), forKey: Key.playlistSharingAcknowledged) }
    }

    init(keychain: any KeychainServiceProtocol, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        provider = defaults.string(forKey: Key.provider).flatMap(AIRecommendationProvider.init(rawValue:)) ?? .appleIntelligence
        anthropicModel = defaults.string(forKey: Key.anthropicModel) ?? ""
        openAIModel = defaults.string(forKey: Key.openAIModel) ?? ""
        sharingAcknowledged = Set((defaults.stringArray(forKey: Key.sharingAcknowledged) ?? [])
            .compactMap(AIRecommendationProvider.init(rawValue:)))
        playlistSharingAcknowledged = Set((defaults.stringArray(forKey: Key.playlistSharingAcknowledged) ?? [])
            .compactMap(AIRecommendationProvider.init(rawValue:)))
    }

    /// The model to ask: the typed one, or the provider's default when the field is empty.
    func model(for provider: AIRecommendationProvider) -> String {
        let typed = switch provider {
        case .appleIntelligence: ""
        case .anthropic: anthropicModel
        case .openAI: openAIModel
        }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel ?? "" : trimmed
    }

    /// True until the user has been told what goes to this provider. Apple Intelligence never asks.
    func needsSharingNotice(for provider: AIRecommendationProvider) -> Bool {
        provider.needsAPIKey && !sharingAcknowledged.contains(provider)
    }

    func acknowledgeSharing(for provider: AIRecommendationProvider) {
        sharingAcknowledged.insert(provider)
    }

    /// True until the user has been told what AI playlists send to this provider.
    func needsPlaylistSharingNotice(for provider: AIRecommendationProvider) -> Bool {
        provider.needsAPIKey && !playlistSharingAcknowledged.contains(provider)
    }

    func acknowledgePlaylistSharing(for provider: AIRecommendationProvider) {
        playlistSharingAcknowledged.insert(provider)
    }

    func apiKey(for provider: AIRecommendationProvider) async -> String? {
        guard provider.needsAPIKey else { return nil }
        await pendingKeySave?.value
        let key = try? await keychain.retrieve(String.self, forKey: provider.keychainKey)
        return key?.isEmpty == false ? key : nil
    }

    func setAPIKey(_ key: String, for provider: AIRecommendationProvider) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try await keychain.delete(forKey: provider.keychainKey) }
        else { try await keychain.store(trimmed, forKey: provider.keychainKey) }
    }

    /// Saves as the user types. Each write waits for the one before it, so the last edit wins.
    func saveAPIKey(_ key: String, for provider: AIRecommendationProvider) {
        let previous = pendingKeySave
        pendingKeySave = Task {
            await previous?.value
            do { try await setAPIKey(key, for: provider) } catch {
                Logger.ui.error("Couldn't save the \(provider.rawValue, privacy: .public) key: \(error, privacy: .public)")
            }
        }
    }
}

/// Gathers the listening profile and library from local data, then runs
/// `AIRecommendationPipeline` with the chosen model: grounded candidates when ListenBrainz is
/// connected, verified free suggestions otherwise.
@MainActor
struct AIRecommender {
    nonisolated static let count = AIRecommendationPipeline.requested

    let container: AppContainer
    let settings: AIRecommendationSettings
    var client = AIRecommendationCloudClient()
    var musicBrainz: any MusicBrainzAlbumLookup = MusicBrainzClient.shared

    func recommend() async throws -> [AIRecommendationResult] {
        guard let server = container.serverState.activeServer else { throw MusicIntentError.noServer }
        let local = try await localData(serverID: server.id)
        guard !local.profile.isEmpty else { throw AIRecommendationError.notEnoughListening }
        let provider = settings.provider
        let model: any AIRecommendationModel
        if provider == .appleIntelligence {
            model = AppleIntelligenceRecommendationModel()
        } else {
            guard let key = await settings.apiKey(for: provider) else { throw AIRecommendationError.missingKey(provider) }
            model = CloudRecommendationModel(client: client, provider: provider, key: key, model: settings.model(for: provider))
        }
        var pipeline = AIRecommendationPipeline(model: model, musicBrainz: musicBrainz, library: local.library)
        let listenBrainz = await container.listenBrainzService.currentSnapshot()
        if listenBrainz.isEnabled {
            pipeline.graph = ListenBrainzArtistGraph(client: ListenBrainzClient(transport: URLSessionListenBrainzTransport()))
            pipeline.username = listenBrainz.username
            pipeline.librarySeeds = local.seeds
        }
        let results = try await pipeline.recommend(local.profile)
        Logger.ui.info("AI recommendations: \(results.count) verified from \(provider.rawValue, privacy: .public)")
        return results
    }

    /// What the listener plays and collects, for AI playlist ideas.
    func listeningProfile() async throws -> AIListeningProfile {
        guard let server = container.serverState.activeServer else { throw MusicIntentError.noServer }
        return try await localData(serverID: server.id).profile
    }

    // MARK: - Local data

    private struct LocalData {
        var profile = AIListeningProfile()
        var library = AIRecommendationLibrary()
        /// The listener's artists with MusicBrainz ids, most played first.
        var seeds: [AIRecommendationArtist] = []
    }

    private func localData(serverID: UUID) async throws -> LocalData {
        var data = LocalData()
        let feed = await HomeFeedCache.shared.load(serverID: serverID)
        if let feed {
            data.profile.recentAlbums = feed.recentlyPlayed.prefix(20).map { "\($0.artist ?? "Unknown") – \($0.name)" }
            data.profile.favoriteAlbums = (feed.favorites?.albums ?? []).prefix(15).map { "\($0.artist ?? "Unknown") – \($0.name)" }
        }
        let store = container.libraryIndexStore
        let albums = try await store.albums(serverID: serverID)
        let artists = try await store.artists(serverID: serverID).flatMap(\.artist)
        var counts: [String: Int] = [:]
        for album in albums { if let artist = album.artist { counts[artist, default: 0] += 1 } }
        data.profile.topArtists = counts.sorted { $0.value > $1.value }.prefix(25).map(\.key)
        data.profile.playlists = try await store.playlists(serverID: serverID)
            .map(\.name).filter { name in Mood.forPlaylistName(name) == nil }.prefix(15).map { $0 }

        data.library = AIRecommendationLibrary(
            albums: albums.map { .init(id: $0.id, name: $0.name, artist: $0.artist ?? $0.displayArtist ?? "", coverArtID: $0.coverArt) },
            artists: artists.map { .init(id: $0.id, name: $0.name, mbid: $0.musicBrainzId) }
        )

        // Seeds: most played, then recently played, then favourite albums' artists, then the most collected.
        let byID = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byName = Dictionary(artists.map { (AIRecommendationMatcher.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        let feedAlbums = (feed?.mostPlayed ?? []) + (feed?.recentlyPlayed ?? []) + (feed?.favorites?.albums ?? [])
        let feedArtists = feedAlbums.compactMap { album in
            album.artistId.flatMap { byID[$0] } ?? album.artist.flatMap { byName[AIRecommendationMatcher.key($0)] }
        }
        let collected = data.profile.topArtists.compactMap { byName[AIRecommendationMatcher.key($0)] }
        var seen = Set<String>()
        data.seeds = (feedArtists + collected).compactMap { artist in
            guard let mbid = artist.musicBrainzId, !mbid.isEmpty, seen.insert(mbid).inserted else { return nil }
            return AIRecommendationArtist(name: artist.name, mbid: mbid)
        }
        return data
    }

    nonisolated static var isAppleIntelligenceAvailable: Bool { SystemLanguageModel.default.isAvailable }
}

// MARK: - Models

/// The on-device model, with guided generation.
nonisolated struct AppleIntelligenceRecommendationModel: AIRecommendationModel {
    @concurrent
    func suggest(_ profile: AIListeningProfile, count: Int) async throws -> [AIRecommendation] {
        let response = try await respond(
            instructions: AIListeningProfile.systemPrompt, prompt: profile.prompt(count: count),
            generating: GeneratedRecommendations.self
        )
        return response.recommendations.map {
            AIRecommendation(artist: $0.artist, album: $0.album, year: $0.year > 0 ? $0.year : nil, reason: $0.reason)
        }
    }

    @concurrent
    func choose(from candidates: [AIRecommendationCandidate], profile: AIListeningProfile, count: Int) async throws -> [AIRecommendationPick] {
        let response = try await respond(
            instructions: AIListeningProfile.choiceSystemPrompt, prompt: profile.choicePrompt(candidates, count: count),
            generating: GeneratedPicks.self
        )
        return response.picks.map { AIRecommendationPick(id: $0.id, reason: $0.reason) }
    }

    private func respond<Content: Generable>(instructions: String, prompt: String, generating type: Content.Type) async throws -> Content {
        guard SystemLanguageModel.default.isAvailable else { throw AIRecommendationError.unavailable }
        let session = LanguageModelSession(instructions: instructions)
        do {
            return try await session.respond(to: prompt, generating: type).content
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.ui.info("On-device recommendations failed: \(error, privacy: .public)")
            throw AIRecommendationError.badResponse
        }
    }
}

/// Anthropic or OpenAI with the user's key.
nonisolated struct CloudRecommendationModel: AIRecommendationModel {
    let client: AIRecommendationCloudClient
    let provider: AIRecommendationProvider
    let key: String
    let model: String

    func suggest(_ profile: AIListeningProfile, count: Int) async throws -> [AIRecommendation] {
        try await client.recommend(profile, provider: provider, key: key, model: model)
    }

    /// The sharing notice lists what goes to the provider, so a candidate's "similar to" names are
    /// limited to artists already in the profile (ListenBrainz's top artists may not be).
    func choose(from candidates: [AIRecommendationCandidate], profile: AIListeningProfile, count: Int) async throws -> [AIRecommendationPick] {
        let shared = Set(profile.artistNames)
        let sent = candidates.map { AIRecommendationCandidate(id: $0.id, album: $0.album, seeds: $0.seeds.filter(shared.contains)) }
        return try await client.choose(from: sent, profile: profile, provider: provider, key: key, model: model)
    }
}

@Generable(description: "Album recommendations for a listener")
nonisolated struct GeneratedRecommendations {
    @Guide(description: "Albums to recommend", .count(12))
    var recommendations: [GeneratedRecommendation]
}

@Generable(description: "Albums chosen from the candidate list")
nonisolated struct GeneratedPicks {
    @Guide(description: "Chosen albums, best first", .maximumCount(12))
    var picks: [GeneratedPick]
}

@Generable
nonisolated struct GeneratedPick {
    @Guide(description: "The candidate's id exactly as listed, such as c3")
    var id: String
    @Guide(description: "One short sentence about the album's sound next to the listener's artist it is similar to, naming only the album, its artist and that artist; no playlists, songs or other albums")
    var reason: String
}

@Generable
nonisolated struct GeneratedRecommendation {
    @Guide(description: "The artist's name")
    var artist: String
    @Guide(description: "The album title")
    var album: String
    @Guide(description: "Release year, or 0 if unsure")
    var year: Int
    @Guide(description: "One short sentence about the album's sound next to one of the listener's artists, naming only that artist and the album's own artist and title; no playlists, songs or other albums")
    var reason: String
}

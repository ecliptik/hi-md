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

    init(keychain: any KeychainServiceProtocol, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        provider = defaults.string(forKey: Key.provider).flatMap(AIRecommendationProvider.init(rawValue:)) ?? .appleIntelligence
        anthropicModel = defaults.string(forKey: Key.anthropicModel) ?? ""
        openAIModel = defaults.string(forKey: Key.openAIModel) ?? ""
        sharingAcknowledged = Set((defaults.stringArray(forKey: Key.sharingAcknowledged) ?? [])
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

/// Builds a listening profile from local data, asks the chosen model for albums, and checks each
/// against the library.
@MainActor
struct AIRecommender {
    nonisolated static let count = 12

    let container: AppContainer
    let settings: AIRecommendationSettings
    var client = AIRecommendationCloudClient()

    func recommend() async throws -> [AIRecommendationResult] {
        guard let server = container.serverState.activeServer else { throw MusicIntentError.noServer }
        let profile = try await listeningProfile(serverID: server.id)
        guard !profile.isEmpty else { throw AIRecommendationError.notEnoughListening }
        let provider = settings.provider
        let items: [AIRecommendation]
        if provider == .appleIntelligence {
            items = try await Self.askAppleIntelligence(profile)
        } else {
            guard let key = await settings.apiKey(for: provider) else { throw AIRecommendationError.missingKey(provider) }
            items = try await client.recommend(profile, provider: provider, key: key, model: settings.model(for: provider))
        }
        Logger.ui.info("AI recommendations: \(items.count) from \(provider.rawValue, privacy: .public)")
        return try await match(items, serverID: server.id)
    }

    // MARK: - Profile

    private func listeningProfile(serverID: UUID) async throws -> AIListeningProfile {
        var profile = AIListeningProfile()
        if let feed = await HomeFeedCache.shared.load(serverID: serverID) {
            profile.recentAlbums = feed.recentlyPlayed.prefix(20).map { "\($0.artist ?? "Unknown") – \($0.name)" }
            profile.favoriteAlbums = (feed.favorites?.albums ?? []).prefix(15).map { "\($0.artist ?? "Unknown") – \($0.name)" }
        }
        let store = container.libraryIndexStore
        let albums = try await store.albums(serverID: serverID)
        var counts: [String: Int] = [:]
        for album in albums { if let artist = album.artist { counts[artist, default: 0] += 1 } }
        profile.topArtists = counts.sorted { $0.value > $1.value }.prefix(25).map(\.key)
        profile.playlists = try await store.playlists(serverID: serverID)
            .map(\.name).filter { name in !Mood.allCases.contains { $0.playlistName == name } }.prefix(15).map { $0 }
        return profile
    }

    // MARK: - Library match

    private func match(_ items: [AIRecommendation], serverID: UUID) async throws -> [AIRecommendationResult] {
        let store = container.libraryIndexStore
        let albums = try await store.albums(serverID: serverID)
        let artists = try await store.artists(serverID: serverID).flatMap(\.artist)
        var albumsByKey: [String: AlbumID3] = [:]
        for album in albums {
            albumsByKey[AIRecommendationMatcher.key(album.artist ?? "") + "|" + AIRecommendationMatcher.key(album.name)] = album
        }
        let artistsByKey = Dictionary(artists.map { (AIRecommendationMatcher.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        return items.map { item in
            let artistKey = AIRecommendationMatcher.key(item.artist)
            if let album = albumsByKey[artistKey + "|" + AIRecommendationMatcher.key(item.album)] {
                return AIRecommendationResult(recommendation: item, availability: .inLibrary(albumID: album.id, coverArtID: album.coverArt))
            }
            if let artist = artistsByKey[artistKey] {
                return AIRecommendationResult(recommendation: item, availability: .artistInLibrary(artistID: artist.id))
            }
            return AIRecommendationResult(recommendation: item, availability: .missing)
        }
    }

    // MARK: - Providers

    // Anthropic and OpenAI go through `AIRecommendationCloudClient`; this is the on-device one.

    nonisolated static var isAppleIntelligenceAvailable: Bool { SystemLanguageModel.default.isAvailable }

    @concurrent
    nonisolated static func askAppleIntelligence(_ profile: AIListeningProfile) async throws -> [AIRecommendation] {
        guard SystemLanguageModel.default.isAvailable else { throw AIRecommendationError.unavailable }
        let session = LanguageModelSession(instructions: AIListeningProfile.systemPrompt)
        do {
            let response = try await session.respond(to: profile.prompt(count: count), generating: GeneratedRecommendations.self)
            return response.content.recommendations.map {
                AIRecommendation(artist: $0.artist, album: $0.album, year: $0.year > 0 ? $0.year : nil, reason: $0.reason)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.ui.info("On-device recommendations failed: \(error, privacy: .public)")
            throw AIRecommendationError.badResponse
        }
    }
}

@Generable(description: "Album recommendations for a listener")
nonisolated struct GeneratedRecommendations {
    @Guide(description: "Albums to recommend", .count(8))
    var recommendations: [GeneratedRecommendation]
}

@Generable
nonisolated struct GeneratedRecommendation {
    @Guide(description: "The artist's name")
    var artist: String
    @Guide(description: "The album title")
    var album: String
    @Guide(description: "Release year, or 0 if unsure")
    var year: Int
    @Guide(description: "One short sentence on why it fits this listener")
    var reason: String
}

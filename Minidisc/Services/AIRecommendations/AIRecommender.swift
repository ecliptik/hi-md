import Foundation
import FoundationModels
import Observation
import OSLog
import SwiftSonic

/// Settings > Integrations > AI Recommendations. API keys live in the keychain.
@Observable
@MainActor
final class AIRecommendationSettings {
    private enum Key {
        static let provider = "ai-recommendations.provider"
        static let anthropicModel = "ai-recommendations.anthropicModel"
        static let openAIModel = "ai-recommendations.openAIModel"
    }

    static let defaultAnthropicModel = "claude-sonnet-5-5"
    static let defaultOpenAIModel = "gpt-5"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: any KeychainServiceProtocol

    var provider: AIRecommendationProvider { didSet { defaults.set(provider.rawValue, forKey: Key.provider) } }
    var anthropicModel: String { didSet { defaults.set(anthropicModel, forKey: Key.anthropicModel) } }
    var openAIModel: String { didSet { defaults.set(openAIModel, forKey: Key.openAIModel) } }

    init(keychain: any KeychainServiceProtocol, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        provider = defaults.string(forKey: Key.provider).flatMap(AIRecommendationProvider.init(rawValue:)) ?? .appleIntelligence
        anthropicModel = defaults.string(forKey: Key.anthropicModel) ?? Self.defaultAnthropicModel
        openAIModel = defaults.string(forKey: Key.openAIModel) ?? Self.defaultOpenAIModel
    }

    func apiKey(for provider: AIRecommendationProvider) async -> String? {
        guard provider.needsAPIKey else { return nil }
        let key = try? await keychain.retrieve(String.self, forKey: provider.keychainKey)
        return key?.isEmpty == false ? key : nil
    }

    func setAPIKey(_ key: String, for provider: AIRecommendationProvider) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try await keychain.delete(forKey: provider.keychainKey) }
        else { try await keychain.store(trimmed, forKey: provider.keychainKey) }
    }

    var model: String {
        switch provider {
        case .appleIntelligence: "on-device"
        case .anthropic: anthropicModel
        case .openAI: openAIModel
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

    func recommend() async throws -> [AIRecommendationResult] {
        guard let server = container.serverState.activeServer else { throw MusicIntentError.noServer }
        let profile = try await listeningProfile(serverID: server.id)
        guard !profile.isEmpty else { throw AIRecommendationError.notEnoughListening }
        let provider = settings.provider
        let items: [AIRecommendation]
        switch provider {
        case .appleIntelligence:
            items = try await Self.askAppleIntelligence(profile)
        case .anthropic:
            guard let key = await settings.apiKey(for: .anthropic) else { throw AIRecommendationError.missingKey }
            items = try await Self.askAnthropic(profile, key: key, model: settings.anthropicModel)
        case .openAI:
            guard let key = await settings.apiKey(for: .openAI) else { throw AIRecommendationError.missingKey }
            items = try await Self.askOpenAI(profile, key: key, model: settings.openAIModel)
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

    nonisolated static func anthropicRequest(_ profile: AIListeningProfile, key: String, model: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": 2048, "system": AIListeningProfile.systemPrompt,
            "messages": [["role": "user", "content": profile.prompt(count: count)]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated static func openAIRequest(_ profile: AIListeningProfile, key: String, model: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": AIListeningProfile.systemPrompt],
                         ["role": "user", "content": profile.prompt(count: count)]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    @concurrent
    nonisolated static func askAnthropic(_ profile: AIListeningProfile, key: String, model: String) async throws -> [AIRecommendation] {
        let data = try await send(anthropicRequest(profile, key: key, model: model))
        struct Response: Decodable { struct Block: Decodable { let type: String; let text: String? }; let content: [Block] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try AIRecommendationParser.parse(response.content.compactMap(\.text).joined())
    }

    @concurrent
    nonisolated static func askOpenAI(_ profile: AIListeningProfile, key: String, model: String) async throws -> [AIRecommendation] {
        let data = try await send(openAIRequest(profile, key: key, model: model))
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try AIRecommendationParser.parse(response.choices.first?.message.content ?? "")
    }

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

    nonisolated private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIRecommendationError.http(status) }
        return data
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

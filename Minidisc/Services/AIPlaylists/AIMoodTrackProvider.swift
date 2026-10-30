import Foundation
import OSLog
import SwiftSonic

/// Lets the AI choose a mood's songs from a wider pool that AudioMuse or the tags gather. When the
/// AI can't answer, or picks too few, the pool's own ranking stands, so a mood is never worse for
/// having AI turned on.
nonisolated struct AIMoodTrackProvider: MoodTrackProvider {
    let base: any MoodTrackProvider
    let model: any AIPlaylistModel
    /// The songs behind track IDs, from the local index; missing ones are left out.
    let songs: @Sendable ([String]) async throws -> [Song]

    var kind: MoodSourceKind { base.kind }

    func prepare() async { await base.prepare() }

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        let poolIDs = try await base.trackIds(for: mood, limit: min(model.candidateLimit, limit * 3))
        let fallback = Array(poolIDs.prefix(limit))
        guard poolIDs.count > limit else { return fallback }
        do {
            let byID = Dictionary(try await songs(poolIDs).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let pool = poolIDs.compactMap { byID[$0] }
            try Task.checkCancellation()
            let choice = try await model.choose(Self.request(for: mood), candidates: AIPlaylistMaker.lines(pool), count: limit)
            let chosen = AIPlaylistMaker.picks(choice.picks, from: pool, limit: limit, perArtist: MoodTagMatcher.perArtistLimit)
            guard chosen.count >= limit / 2 else {
                Logger.moodPlaylists.info("[MOOD-AI] \(mood.rawValue, privacy: .public): only \(chosen.count) picks; keeping the pool's ranking")
                return fallback
            }
            Logger.moodPlaylists.info("[MOOD-AI] \(mood.rawValue, privacy: .public): chose \(chosen.count) of \(pool.count)")
            return chosen.map(\.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.moodPlaylists.info("[MOOD-AI] \(mood.rawValue, privacy: .public) failed, keeping the pool's ranking: \(error, privacy: .public)")
            return fallback
        }
    }

    static func request(for mood: Mood) -> String {
        switch mood {
        case .night: "A late-night playlist: calm, atmospheric, quiet songs for after dark."
        case .energetic: "An energetic playlist: upbeat, lively, feel-good songs."
        case .workout: "A workout playlist: intense, driving, high-tempo songs."
        case .chill: "A chill playlist: relaxed, mellow, laid-back songs."
        case .focus: "A focus playlist: calm, steady, mostly instrumental background music."
        }
    }
}

/// Which AI makes playlists: the provider chosen in Settings > AI Recommendations.
@MainActor
enum AIPlaylistModels {
    /// The chosen provider, or why it can't be used yet.
    static func current(_ settings: AIRecommendationSettings, client: AIRecommendationCloudClient = AIRecommendationCloudClient()) async throws -> any AIPlaylistModel {
        let provider = settings.provider
        guard provider.needsAPIKey else {
            guard AIRecommender.isAppleIntelligenceAvailable else { throw AIRecommendationError.unavailable }
            return AppleIntelligencePlaylistModel()
        }
        guard let key = await settings.apiKey(for: provider) else { throw AIRecommendationError.missingKey(provider) }
        return CloudPlaylistModel(client: client, provider: provider, key: key, model: settings.model(for: provider))
    }

    /// For the weekly moods, which run unattended: a provider that's ready, and a cloud one only
    /// once the listener has agreed to send it song names.
    static func unattended(_ settings: AIRecommendationSettings) async -> (any AIPlaylistModel)? {
        if settings.needsPlaylistSharingNotice(for: settings.provider) { return nil }
        return try? await current(settings)
    }

    static func unattended(keychain: any KeychainServiceProtocol, defaults: UserDefaults) async -> (any AIPlaylistModel)? {
        await unattended(AIRecommendationSettings(keychain: keychain, defaults: defaults))
    }
}

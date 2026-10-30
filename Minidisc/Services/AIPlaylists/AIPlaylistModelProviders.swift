import Foundation
import FoundationModels
import OSLog

/// The on-device model. Its context is small, so it plans from genres alone and chooses from a
/// short list.
nonisolated struct AppleIntelligencePlaylistModel: AIPlaylistModel {
    var plansWithArtists: Bool { false }
    var candidateLimit: Int { 60 }

    @concurrent
    func plan(_ request: String, library: AIPlaylistLibrarySummary) async throws -> AIPlaylistPlan {
        let summary = AIPlaylistLibrarySummary(genres: Array(library.genres.prefix(120)), artists: [])
        let plan = try await respond(instructions: AIPlaylistPrompts.planSystem,
                                     prompt: AIPlaylistPrompts.planPrompt(request, library: summary),
                                     generating: GeneratedPlaylistPlan.self)
        return AIPlaylistPlan(genres: plan.genres, artists: [],
                              years: AIPlaylistParser.years(from: plan.fromYear, to: plan.toYear), mood: plan.mood.mood)
    }

    @concurrent
    func choose(_ request: String, candidates: [String], count: Int) async throws -> AIPlaylistChoice {
        let choice = try await respond(instructions: AIPlaylistPrompts.chooseSystem,
                                       prompt: AIPlaylistPrompts.choosePrompt(request, candidates: candidates, count: count),
                                       generating: GeneratedPlaylistChoice.self)
        return AIPlaylistChoice(title: choice.title, summary: choice.summary, picks: choice.picks)
    }

    @concurrent
    func ideas(_ profile: AIListeningProfile, genres: [String], count: Int) async throws -> [AIPlaylistIdea] {
        let ideas = try await respond(instructions: AIPlaylistPrompts.ideasSystem,
                                      prompt: AIPlaylistPrompts.ideasPrompt(profile, genres: Array(genres.prefix(40)), count: count),
                                      generating: GeneratedPlaylistIdeas.self)
        return ideas.ideas.map { AIPlaylistIdea(title: $0.title, prompt: $0.prompt) }
    }

    private func respond<Content: Generable>(instructions: String, prompt: String, generating type: Content.Type) async throws -> Content {
        guard SystemLanguageModel.default.isAvailable else { throw AIRecommendationError.unavailable }
        let session = LanguageModelSession(instructions: instructions)
        do {
            return try await session.respond(to: prompt, generating: type).content
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.ui.info("On-device playlist request failed: \(error, privacy: .public)")
            throw AIRecommendationError.badResponse
        }
    }
}

/// Claude or ChatGPT with the listener's key. They know artists well, so planning also sees the
/// library's artist names, and they choose from a longer list.
nonisolated struct CloudPlaylistModel: AIPlaylistModel {
    let client: AIRecommendationCloudClient
    let provider: AIRecommendationProvider
    let key: String
    let model: String

    var plansWithArtists: Bool { true }
    var candidateLimit: Int { 250 }

    func plan(_ request: String, library: AIPlaylistLibrarySummary) async throws -> AIPlaylistPlan {
        let text = try await client.complete(
            system: AIPlaylistPrompts.planSystem + "\n\n" + AIPlaylistPrompts.planJSON,
            user: AIPlaylistPrompts.planPrompt(request, library: library),
            provider: provider, key: key, model: model
        )
        return try AIPlaylistParser.plan(text)
    }

    func choose(_ request: String, candidates: [String], count: Int) async throws -> AIPlaylistChoice {
        let text = try await client.complete(
            system: AIPlaylistPrompts.chooseSystem + "\n\n" + AIPlaylistPrompts.chooseJSON,
            user: AIPlaylistPrompts.choosePrompt(request, candidates: candidates, count: count),
            provider: provider, key: key, model: model
        )
        return try AIPlaylistParser.choice(text)
    }

    func ideas(_ profile: AIListeningProfile, genres: [String], count: Int) async throws -> [AIPlaylistIdea] {
        let text = try await client.complete(
            system: AIPlaylistPrompts.ideasSystem + "\n\n" + AIPlaylistPrompts.ideasJSON,
            user: AIPlaylistPrompts.ideasPrompt(profile, genres: Array(genres.prefix(80)), count: count),
            provider: provider, key: key, model: model
        )
        return try AIPlaylistParser.ideas(text)
    }
}

@Generable(description: "What a playlist request means in terms of the library")
nonisolated struct GeneratedPlaylistPlan {
    @Guide(description: "Genres from the library's list that fit the request, written exactly as listed. Empty if none fit.")
    var genres: [String]
    @Guide(description: "Earliest release year if the request names a period, otherwise 0")
    var fromYear: Int
    @Guide(description: "Latest release year if the request names a period, otherwise 0")
    var toYear: Int
    @Guide(description: "The mood that fits the request best, or none")
    var mood: GeneratedMood
}

@Generable(description: "A playlist chosen from numbered songs")
nonisolated struct GeneratedPlaylistChoice {
    @Guide(description: "A short, plain playlist title of at most five words, without quotation marks or emoji")
    var title: String
    @Guide(description: "One sentence describing the playlist")
    var summary: String
    @Guide(description: "The chosen songs' numbers exactly as listed, in the order to play them")
    var picks: [Int]
}

@Generable(description: "Playlist ideas for a listener")
nonisolated struct GeneratedPlaylistIdeas {
    @Guide(description: "Different playlist ideas", .count(5))
    var ideas: [GeneratedPlaylistIdea]
}

@Generable
nonisolated struct GeneratedPlaylistIdea {
    @Guide(description: "A short title of at most five words, without emoji")
    var title: String
    @Guide(description: "The request that makes this playlist, as the listener might type it")
    var prompt: String
}

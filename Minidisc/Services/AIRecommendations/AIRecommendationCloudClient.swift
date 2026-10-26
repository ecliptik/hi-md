import Foundation
import OSLog

/// Anthropic's Messages API and OpenAI's chat completions over plain HTTPS, with the user's own
/// key. The prompt asks for JSON and `AIRecommendationParser` reads it, so every provider ends
/// up with the same `[AIRecommendation]`. No retries: the screen says what went wrong instead.
nonisolated struct AIRecommendationCloudClient: Sendable {
    static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let timeout: TimeInterval = 90
    /// Room for twelve albums plus whatever the model spends thinking first.
    static let maxTokens = 8192

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.timeout
            config.timeoutIntervalForResource = Self.timeout
            self.session = URLSession(configuration: config)
        }
    }

    @concurrent
    func recommend(_ profile: AIListeningProfile, provider: AIRecommendationProvider, key: String, model: String) async throws -> [AIRecommendation] {
        let request = try Self.request(
            provider, key: key, model: model, system: AIListeningProfile.systemPrompt,
            user: profile.prompt(count: AIRecommender.count), maxTokens: Self.maxTokens
        )
        let data = try await send(request, provider: provider, model: model)
        return try AIRecommendationParser.parse(Self.replyText(from: data, provider: provider))
    }

    /// Picks from verified candidates by id. The pipeline drops ids that aren't on the list.
    @concurrent
    func choose(
        from candidates: [AIRecommendationCandidate], profile: AIListeningProfile,
        provider: AIRecommendationProvider, key: String, model: String
    ) async throws -> [AIRecommendationPick] {
        let request = try Self.request(
            provider, key: key, model: model, system: AIListeningProfile.choiceSystemPrompt,
            user: profile.choicePrompt(candidates, count: AIRecommender.count), maxTokens: Self.maxTokens
        )
        let data = try await send(request, provider: provider, model: model)
        return try AIRecommendationParser.parsePicks(Self.replyText(from: data, provider: provider))
    }

    /// The smallest round trip that proves the key and model work. Sends no listening data, and
    /// only the status matters: a short cap can leave a thinking model with no text to return.
    @concurrent
    func testConnection(provider: AIRecommendationProvider, key: String, model: String) async throws {
        let request = try Self.request(provider, key: key, model: model, system: "Reply with OK.", user: "ping", maxTokens: 16)
        _ = try await send(request, provider: provider, model: model)
    }

    // MARK: - Requests

    struct AnthropicRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        private enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    struct OpenAIRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct ResponseFormat: Encodable { let type: String }
        let model: String
        let messages: [Message]
        /// `max_tokens` is rejected by the GPT-5 family.
        let maxCompletionTokens: Int
        let responseFormat: ResponseFormat

        private enum CodingKeys: String, CodingKey {
            case model, messages
            case maxCompletionTokens = "max_completion_tokens"
            case responseFormat = "response_format"
        }
    }

    static func request(
        _ provider: AIRecommendationProvider, key: String, model: String, system: String, user: String, maxTokens: Int
    ) throws -> URLRequest {
        var request: URLRequest
        switch provider {
        case .appleIntelligence:
            throw AIRecommendationError.badResponse
        case .anthropic:
            request = URLRequest(url: anthropicEndpoint)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(AnthropicRequest(
                model: model, maxTokens: maxTokens, system: system, messages: [.init(role: "user", content: user)]
            ))
        case .openAI:
            request = URLRequest(url: openAIEndpoint)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(OpenAIRequest(
                model: model,
                messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
                maxCompletionTokens: maxTokens, responseFormat: .init(type: "json_object")
            ))
        }
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    // MARK: - Responses

    /// The model's text out of each provider's envelope. Anthropic replies may lead with
    /// thinking blocks, which carry no text; a refusal is an answer Minidisc can't use.
    static func replyText(from data: Data, provider: AIRecommendationProvider) throws -> String {
        let decoder = JSONDecoder()
        let text: String
        switch provider {
        case .appleIntelligence:
            throw AIRecommendationError.badResponse
        case .anthropic:
            struct Envelope: Decodable {
                struct Block: Decodable { let type: String; let text: String? }
                let content: [Block]
                let stopReason: String?

                private enum CodingKeys: String, CodingKey {
                    case content
                    case stopReason = "stop_reason"
                }
            }
            guard let envelope = try? decoder.decode(Envelope.self, from: data), envelope.stopReason != "refusal" else {
                throw AIRecommendationError.badResponse
            }
            text = envelope.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        case .openAI:
            struct Envelope: Decodable {
                struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
                let choices: [Choice]
            }
            guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw AIRecommendationError.badResponse }
            text = envelope.choices.first?.message.content ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRecommendationError.badResponse }
        return text
    }

    /// Maps a failed status to what the screen says. 401 and 403 mean the key; 404 the model.
    static func error(status: Int, body: Data, provider: AIRecommendationProvider, model: String) -> AIRecommendationError {
        switch status {
        case 401, 403: .rejectedKey(provider)
        case 404: .unknownModel(provider, model)
        case 429: .rateLimited(provider)
        case 408, 500...599: .serviceBusy(provider)
        default: .http(provider, status: status, message: errorMessage(from: body))
        }
    }

    /// The readable message in an error body. Both providers use `{"error": {"message": …}}`.
    static func errorMessage(from data: Data) -> String? {
        struct Envelope: Decodable { struct Detail: Decodable { let message: String? }; let error: Detail }
        guard let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message?
            .trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else { return nil }
        return String(message.prefix(200))
    }

    private func send(_ request: URLRequest, provider: AIRecommendationProvider, model: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw AIRecommendationError.offline(provider)
        }
        guard let http = response as? HTTPURLResponse else { throw AIRecommendationError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Only the status: an error body can quote part of the key back.
            Logger.ui.notice("AI recommendations: \(provider.rawValue, privacy: .public) returned \(http.statusCode)")
            throw Self.error(status: http.statusCode, body: data, provider: provider, model: model)
        }
        return data
    }
}

import Foundation
import Synchronization
import Testing
@testable import Minidisc

/// Answers every request with one canned status and body, or a transport error, and keeps the
/// last request so its headers and body can be checked. No real network.
private nonisolated final class CloudStubProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status = 200
        var body = ""
        var failure: URLError.Code?
    }

    struct Captured: Sendable {
        var request: URLRequest?
        var body: Data?
    }

    private static let stub = Mutex(Stub())
    private static let captured = Mutex(Captured())

    static func respond(status: Int = 200, body: String = "", failure: URLError.Code? = nil) {
        stub.withLock { $0 = Stub(status: status, body: body, failure: failure) }
        captured.withLock { $0 = Captured() }
    }

    static var lastRequest: URLRequest? { captured.withLock { $0.request } }
    static var lastBody: [String: Any]? {
        captured.withLock { $0.body }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol moves httpBody into httpBodyStream, so read it back out.
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let request = self.request
        Self.captured.withLock { $0 = Captured(request: request, body: body) }
        let stub = Self.stub.withLock { $0 }
        if let failure = stub.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("AI recommendation cloud client", .serialized)
struct AIRecommendationCloudClientTests {
    private let fixtureKey = "test-key-fixture"
    private var profile: AIListeningProfile {
        var profile = AIListeningProfile()
        profile.recentAlbums = ["Radiohead – OK Computer"]
        profile.topArtists = ["Björk"]
        return profile
    }

    private func makeClient() -> (AIRecommendationCloudClient, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudStubProtocol.self]
        let session = URLSession(configuration: config)
        return (AIRecommendationCloudClient(session: session), session)
    }

    private let recommendationsJSON = #"{\"recommendations\": [{\"artist\": \"Radiohead\", \"album\": \"In Rainbows\", \"year\": 2007, \"reason\": \"r\"}]}"#

    // MARK: - Requests

    @Test func anthropicRequestCarriesKeyVersionModelAndProfile() async throws {
        CloudStubProtocol.respond(body: #"{"content": [{"type": "text", "text": "\#(recommendationsJSON)"}], "stop_reason": "end_turn"}"#)
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }

        _ = try await client.recommend(profile, provider: .anthropic, key: fixtureKey, model: "claude-opus-5-5")

        let request = try #require(CloudStubProtocol.lastRequest)
        #expect(request.url == AIRecommendationCloudClient.anthropicEndpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == fixtureKey)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(CloudStubProtocol.lastBody)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == AIRecommendationCloudClient.maxTokens)
        #expect(body["system"] as? String == AIListeningProfile.systemPrompt)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        let prompt = try #require(messages[0]["content"] as? String)
        #expect(prompt.contains("OK Computer") && prompt.contains("Björk"))
    }

    @Test func openAIRequestUsesBearerJSONModeAndCompletionTokens() async throws {
        CloudStubProtocol.respond(body: #"{"choices": [{"message": {"role": "assistant", "content": "\#(recommendationsJSON)"}}]}"#)
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }

        _ = try await client.recommend(profile, provider: .openAI, key: fixtureKey, model: "gpt-5.6-terra")

        let request = try #require(CloudStubProtocol.lastRequest)
        #expect(request.url == AIRecommendationCloudClient.openAIEndpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixtureKey)")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
        let body = try #require(CloudStubProtocol.lastBody)
        #expect(body["model"] as? String == "gpt-5.6-terra")
        #expect(body["max_completion_tokens"] as? Int == AIRecommendationCloudClient.maxTokens)
        #expect(body["max_tokens"] == nil, "the GPT-5 family rejects max_tokens")
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        #expect(messages[0]["content"] as? String == AIListeningProfile.systemPrompt)
    }

    @Test func connectionTestSendsNoListeningData() async throws {
        CloudStubProtocol.respond(body: #"{"content": [], "stop_reason": "max_tokens"}"#)
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }

        try await client.testConnection(provider: .anthropic, key: fixtureKey, model: "claude-haiku-5-5")

        let body = try #require(CloudStubProtocol.lastBody)
        #expect(body["model"] as? String == "claude-haiku-5-5")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["content"] as? String == "ping")
    }

    // MARK: - Responses

    @Test func bothProvidersYieldTheSameRecommendations() async throws {
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }
        let expected = [AIRecommendation(artist: "Radiohead", album: "In Rainbows", year: 2007, reason: "r")]

        // Anthropic replies may lead with an empty thinking block.
        CloudStubProtocol.respond(body: """
            {"content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "```json\\n\(recommendationsJSON)\\n```"}],
             "stop_reason": "end_turn"}
            """)
        #expect(try await client.recommend(profile, provider: .anthropic, key: fixtureKey, model: "m") == expected)

        CloudStubProtocol.respond(body: #"{"choices": [{"message": {"content": "\#(recommendationsJSON)"}}]}"#)
        #expect(try await client.recommend(profile, provider: .openAI, key: fixtureKey, model: "m") == expected)
    }

    @Test func refusalsAndEmptyRepliesAreBadResponses() throws {
        let refusal = Data(#"{"content": [{"type": "text", "text": "{}"}], "stop_reason": "refusal"}"#.utf8)
        #expect(throws: AIRecommendationError.badResponse) {
            try AIRecommendationCloudClient.replyText(from: refusal, provider: .anthropic)
        }
        let empty = Data(#"{"choices": [{"message": {"content": null}}]}"#.utf8)
        #expect(throws: AIRecommendationError.badResponse) {
            try AIRecommendationCloudClient.replyText(from: empty, provider: .openAI)
        }
        #expect(throws: AIRecommendationError.badResponse) {
            try AIRecommendationCloudClient.replyText(from: Data("not json".utf8), provider: .anthropic)
        }
    }

    // MARK: - Errors

    @Test(arguments: [
        (401, AIRecommendationError.rejectedKey(.anthropic)),
        (403, .rejectedKey(.anthropic)),
        (404, .unknownModel(.anthropic, "claude-nope")),
        (429, .rateLimited(.anthropic)),
        (500, .serviceBusy(.anthropic)),
        (529, .serviceBusy(.anthropic))
    ])
    func statusCodesMapToClearErrors(status: Int, expected: AIRecommendationError) async {
        CloudStubProtocol.respond(status: status, body: #"{"type": "error", "error": {"type": "x", "message": "m"}}"#)
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }

        await #expect(throws: expected) {
            try await client.recommend(profile, provider: .anthropic, key: fixtureKey, model: "claude-nope")
        }
    }

    @Test func otherStatusesKeepTheProvidersMessage() async {
        CloudStubProtocol.respond(status: 400, body: #"{"error": {"message": "  Unsupported value: 'temperature'.  "}}"#)
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }

        let expected = AIRecommendationError.http(.openAI, status: 400, message: "Unsupported value: 'temperature'.")
        await #expect(throws: expected) {
            try await client.recommend(profile, provider: .openAI, key: fixtureKey, model: "m")
        }
        #expect(expected.detail == "Unsupported value: 'temperature'.")
        #expect(expected.isFixedInSettings)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost])
    func transportFailuresAreOffline(code: URLError.Code) async {
        CloudStubProtocol.respond(failure: code)
        let (client, session) = makeClient()
        defer { session.invalidateAndCancel() }

        await #expect(throws: AIRecommendationError.offline(.openAI)) {
            try await client.recommend(profile, provider: .openAI, key: fixtureKey, model: "m")
        }
    }

    @Test func messagesNameTheProviderAndPointAtSettings() {
        let missing = String(localized: AIRecommendationError.missingKey(.anthropic).localizedStringResource)
        #expect(missing.contains("Anthropic") && missing.contains("AI Recommendations"))
        #expect(AIRecommendationError.missingKey(.openAI).isFixedInSettings)
        #expect(AIRecommendationError.rejectedKey(.openAI).isFixedInSettings)
        #expect(!AIRecommendationError.rateLimited(.openAI).isFixedInSettings)
        #expect(!AIRecommendationError.offline(.anthropic).isFixedInSettings)
        #expect(AIRecommendationError.rejectedKey(.anthropic).detail == nil)
    }
}

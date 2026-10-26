import Foundation
import Testing
@testable import Minidisc

@MainActor
private final class RecommendationKeychain: KeychainServiceProtocol {
    private(set) var storage: [String: Data] = [:]

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) async throws {
        storage[key] = nil
    }
}

@Suite("AI recommendation settings")
@MainActor
struct AIRecommendationSettingsTests {
    @Test func providerAndModelsPersistAcrossLaunches() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = RecommendationKeychain()

        let settings = AIRecommendationSettings(keychain: keychain, defaults: defaults)
        #expect(settings.provider == .appleIntelligence)
        settings.provider = .anthropic
        settings.anthropicModel = "claude-haiku-5-5"
        settings.openAIModel = "gpt-custom"

        let restored = AIRecommendationSettings(keychain: keychain, defaults: defaults)
        #expect(restored.provider == .anthropic)
        #expect(restored.model(for: .anthropic) == "claude-haiku-5-5")
        #expect(restored.model(for: .openAI) == "gpt-custom")
    }

    @Test func emptyOrUnknownValuesFallBackToDefaults() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("gemini", forKey: "ai-recommendations.provider")
        defaults.set("   ", forKey: "ai-recommendations.anthropicModel")

        let settings = AIRecommendationSettings(keychain: RecommendationKeychain(), defaults: defaults)
        #expect(settings.provider == .appleIntelligence)
        #expect(settings.model(for: .anthropic) == "claude-opus-5-5")
        #expect(settings.model(for: .openAI) == "gpt-5.6-terra")
        #expect(settings.model(for: .appleIntelligence).isEmpty)
    }

    @Test func sharingNoticeIsShownOncePerCloudProvider() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = RecommendationKeychain()

        let settings = AIRecommendationSettings(keychain: keychain, defaults: defaults)
        #expect(!settings.needsSharingNotice(for: .appleIntelligence))
        #expect(settings.needsSharingNotice(for: .anthropic))
        settings.acknowledgeSharing(for: .anthropic)

        let restored = AIRecommendationSettings(keychain: keychain, defaults: defaults)
        #expect(!restored.needsSharingNotice(for: .anthropic))
        #expect(restored.needsSharingNotice(for: .openAI), "a different provider gets its own notice")
    }

    @Test func keysLiveInTheKeychainNotDefaults() async {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = RecommendationKeychain()
        let settings = AIRecommendationSettings(keychain: keychain, defaults: defaults)

        // Saved as typed: only the last edit should stick, trimmed.
        settings.saveAPIKey("fixture-a", for: .anthropic)
        settings.saveAPIKey("fixture-ab", for: .anthropic)
        settings.saveAPIKey(" fixture-abc \n", for: .anthropic)
        #expect(await settings.apiKey(for: .anthropic) == "fixture-abc")
        #expect(await settings.apiKey(for: .openAI) == nil)
        #expect(await settings.apiKey(for: .appleIntelligence) == nil)
        #expect(keychain.storage.keys.sorted() == ["ai-recommendations.anthropic"])
        let stored = defaults.dictionaryRepresentation().values.compactMap { $0 as? String }
        #expect(!stored.contains { $0.contains("fixture") })

        settings.saveAPIKey("", for: .anthropic)
        #expect(await settings.apiKey(for: .anthropic) == nil)
        #expect(keychain.storage.isEmpty)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "app.minidisc.tests.ai-recommendations.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

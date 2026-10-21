import Foundation
import Testing
@testable import Minidisc

// A locally signed Mac Catalyst build has no application identifier, so the keychain refuses
// it (-34018) until the Mac app is signed with a provisioning profile.
#if targetEnvironment(macCatalyst)
private nonisolated let keychainAvailable = false
#else
private nonisolated let keychainAvailable = true
#endif

@Suite("Keychain", .serialized, .enabled(if: keychainAvailable))
struct KeychainServiceTests {
    @Test func storesLoadsAndDeletesCredentials() async throws {
        let keychain = KeychainService()
        let key = "test-\(UUID().uuidString)"
        try await keychain.store("secret", forKey: key)
        #expect(try await keychain.retrieve(String.self, forKey: key) == "secret")
        try await keychain.delete(forKey: key)
        #expect(try await keychain.retrieve(String.self, forKey: key) == nil)
    }
}

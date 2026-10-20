import Foundation

/// Validation shared by the settings that store a credential next to a user-typed server address.
nonisolated enum IntegrationEndpoint {
    /// Accepts only http and https addresses that name a host. Other schemes, such as `ftp:` or
    /// `file:`, can never reach a credential-checking API.
    static func validatedURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    /// True when the address would send its credential without encryption.
    static func isCleartext(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://")
    }
}

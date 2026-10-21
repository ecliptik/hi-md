import SwiftUI

private struct MinidiscPlayingAccentKey: EnvironmentKey {
    // RootView sets the chosen accent; this is only the fallback outside it.
    static let defaultValue = Color(.minidiscBrandGold)
}

extension EnvironmentValues {
    /// Override with accentForeground(on:) when indicators sit on artwork-derived backgrounds.
    var minidiscPlayingAccent: Color {
        get { self[MinidiscPlayingAccentKey.self] }
        set { self[MinidiscPlayingAccentKey.self] = newValue }
    }
}

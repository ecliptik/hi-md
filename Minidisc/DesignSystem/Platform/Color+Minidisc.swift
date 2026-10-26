import SwiftUI

extension Color {
    nonisolated static var minidiscSystemBackground: Color {
        #if os(macOS)
        Color(.windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    nonisolated static let minidiscAccentText = Color.white

    nonisolated static let minidiscCoverShadow = Color(red: 0, green: 0, blue: 0, opacity: 0.15)

    nonisolated static let minidiscCoverBorder = Color.white.opacity(0.08)
}

import Observation
import SwiftUI
import UIKit

/// The accent colours offered in Settings > Appearance. Gold comes from the 💽 icon.
nonisolated enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case gold, coral, red, orange, pink, purple, blue, teal, green

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .gold: "Gold"
        case .coral: "Coral"
        case .red: "Red"
        case .orange: "Orange"
        case .pink: "Pink"
        case .purple: "Purple"
        case .blue: "Blue"
        case .teal: "Teal"
        case .green: "Green"
        }
    }

    /// Light and dark variants, each dark enough for white text in light mode and bright enough
    /// to read on black in dark mode.
    private var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .gold: (0x926A0C, 0x9A6D04)
        case .coral: (0xC2483A, 0xF0735F)
        case .red: (0xC0262D, 0xFF5A52)
        case .orange: (0xB45309, 0xFB923C)
        case .pink: (0xC0306B, 0xF472B6)
        case .purple: (0x7E3FC4, 0xC084FC)
        case .blue: (0x1F5FC4, 0x60A5FA)
        case .teal: (0x0F766E, 0x2DD4BF)
        case .green: (0x2F7D32, 0x4ADE80)
        }
    }

    @MainActor var color: Color {
        // Gold keeps the asset catalog colour the brand was tuned with.
        if self == .gold { return Color(.minidiscBrandGold) }
        let (light, dark) = hex
        return Color(uiColor: Self.dynamicColor(light: light, dark: dark))
    }

    /// Nonisolated so the provider closure is too: SwiftUI resolves colours on its render
    /// thread, and a main-actor closure would trap there.
    private static func dynamicColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light) }
    }
}

/// How album, playlist and artist screens are coloured.
nonisolated enum DetailScreenStyle: String, CaseIterable, Identifiable, Sendable {
    /// A black background with white text; the accent colour marks the Play button.
    case black
    /// The background takes its colours from the cover art.
    case coverColors

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .black: "Black"
        case .coverColors: "Cover Colours"
        }
    }
}

/// App-wide appearance choices. Views that read these redraw when they change, so the accent
/// colour updates everywhere without restarting the app.
@Observable
@MainActor
final class AppearanceSettings {
    static let shared = AppearanceSettings(defaults: .standard)
    static let accentKey = "minidisc.accentColor"
    static let detailStyleKey = "minidisc.detailScreenStyle"

    @ObservationIgnored private let defaults: UserDefaults

    var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: Self.accentKey) }
    }

    var detailStyle: DetailScreenStyle {
        didSet { defaults.set(detailStyle.rawValue, forKey: Self.detailStyleKey) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        accent = defaults.string(forKey: Self.accentKey).flatMap(AccentChoice.init(rawValue:)) ?? .gold
        detailStyle = defaults.string(forKey: Self.detailStyleKey).flatMap(DetailScreenStyle.init(rawValue:)) ?? .black
    }
}

extension Color {
    /// The accent colour chosen in Settings > Appearance.
    static var minidiscAccent: Color { AppearanceSettings.shared.accent.color }
}

extension ShapeStyle where Self == Color {
    static var minidiscAccent: Color { Color.minidiscAccent }
}

private nonisolated extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

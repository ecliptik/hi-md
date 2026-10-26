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

    /// Light and dark variants. Both carry white text at 4.5:1 or more (WCAG AA), since the
    /// accent fills prominent buttons, chips and pickers. The dark variants sit in gold's
    /// luminance band (about 0.178), which also keeps them at about 4.2:1 on the black
    /// background, the same as gold. Hues were kept by retuning only OKLab lightness.
    ///
    /// White on the dark variant, before and after the 2026-10-25 accessibility audit (H1):
    /// coral 2.87 → 4.61 (#F0735F → #C64E3C), red 3.07 → 4.60 (#FF5A52 → #DB3533),
    /// orange 2.26 → 4.62 (#FB923C → #B45E07), pink 2.65 → 4.60 (#F472B6 → #C3468B),
    /// purple 2.64 → 4.61 (#C084FC → #9558CD), blue 2.54 → 4.60 (#60A5FA → #3276C8),
    /// teal 1.86 → 4.60 (#2DD4BF → #038475), green 1.74 → 4.61 (#4ADE80 → #088744).
    /// Gold (#9A6D04, 4.60) was already in the band. `AccentContrastTests` holds the line.
    var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .gold: (0x926A0C, 0x9A6D04) // mirrors the MinidiscBrandGold asset
        case .coral: (0xC2483A, 0xC64E3C)
        case .red: (0xC0262D, 0xDB3533)
        case .orange: (0xB45309, 0xB45E07)
        case .pink: (0xC0306B, 0xC3468B)
        case .purple: (0x7E3FC4, 0x9558CD)
        case .blue: (0x1F5FC4, 0x3276C8)
        case .teal: (0x0F766E, 0x038475)
        case .green: (0x2F7D32, 0x088744)
        }
    }

    @MainActor var color: Color {
        // Gold keeps the asset catalog colour the brand was tuned with.
        if self == .gold { return Color(.minidiscBrandGold) }
        let (light, dark) = hex
        return Color(uiColor: Self.dynamicColor(light: light, dark: dark))
    }

    /// For filled buttons with white text: the deeper light-mode shade in both appearances,
    /// so hero Play buttons look the same whatever the device appearance.
    @MainActor var fillColor: Color {
        if self == .gold { return Color(.minidiscBrandGold).resolvedLight }
        return Color(uiColor: UIColor(rgb: hex.light))
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

private extension Color {
    /// This colour as it appears in light mode.
    var resolvedLight: Color {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        return Color(resolve(in: environment))
    }
}

private nonisolated extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

import SwiftUI

/// The home-screen icons: the gold primary icon and the two alternates listed in
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
nonisolated enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case gold, dark, light

    var id: String { rawValue }

    /// The name `setAlternateIconName` takes; nil selects the primary icon.
    var alternateIconName: String? {
        switch self {
        case .gold: nil
        case .dark: "AppIconDark"
        case .light: "AppIconLight"
        }
    }

    /// The choice for the icon iOS reports as current. An unknown name falls back to the primary icon.
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .gold
    }

    var title: LocalizedStringResource {
        switch self {
        case .gold: "Gold"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    /// A copy of the icon for the picker: app icons can't be loaded as images.
    @MainActor var preview: ImageResource {
        switch self {
        case .gold: .appIconPreviewGold
        case .dark: .appIconPreviewDark
        case .light: .appIconPreviewLight
        }
    }
}

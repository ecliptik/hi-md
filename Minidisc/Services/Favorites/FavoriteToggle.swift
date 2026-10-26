import Foundation

/// How a favourite heart looks and what clicking it does, for a song, album or artist. The Mac's
/// heart buttons and the Add to/Remove from Favorites menu items share it, so they always agree.
nonisolated struct FavoriteToggle: Sendable, Hashable {
    let isFavorite: Bool

    init(isFavorite: Bool) {
        self.isFavorite = isFavorite
    }

    /// The heart in a button: filled once starred.
    var systemImage: String { isFavorite ? "heart.fill" : "heart" }

    /// The icon beside the menu item, which shows what choosing it does.
    var menuSystemImage: String { isFavorite ? "heart.slash" : "heart" }

    /// What clicking does, for menu items and help tags.
    var actionTitle: LocalizedStringResource { isFavorite ? "Remove from Favorites" : "Add to Favorites" }

    /// The heart's accessibility value; its label is "Favorite".
    var accessibilityValue: LocalizedStringResource { isFavorite ? "On" : "Off" }

    /// The value to set when the heart is clicked.
    var toggled: Bool { !isFavorite }

    /// `FavoriteRecord.id` for an item: "{type}:{id}", e.g. "album:abc123".
    static func recordID(_ type: FavoriteType, id: String) -> String {
        "\(type.rawValue):\(id)"
    }
}

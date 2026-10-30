import SwiftData
import SwiftUI

/// Whether one album, artist or song is starred, read from the same `FavoriteRecord` store the
/// iPhone's hearts query. Star and unstar write that store first, so every heart and menu item
/// showing the item changes together, and a failed server call puts it back.
struct FavoriteMatches<Content: View>: View {
    @Query private var matches: [FavoriteRecord]
    private let content: (FavoriteToggle) -> Content

    init(_ itemType: FavoriteType, id: String, @ViewBuilder content: @escaping (FavoriteToggle) -> Content) {
        let recordID = FavoriteToggle.recordID(itemType, id: id)
        _matches = Query(filter: #Predicate<FavoriteRecord> { $0.id == recordID })
        self.content = content
    }

    var body: some View {
        content(FavoriteToggle(isFavorite: !matches.isEmpty))
    }
}

/// The heart beside Play and Shuffle in an album's or artist's header: filled in the accent
/// colour once starred. Clicking stars or unstars the item on the server.
struct MacFavoriteButton: View {
    let itemType: FavoriteType
    let itemID: String

    @Environment(MacPlayback.self) private var playback
    @Environment(\.minidiscPlayingAccent) private var accent

    var body: some View {
        FavoriteMatches(itemType, id: itemID) { toggle in
            Button {
                playback.setFavorite(toggle.toggled, itemType: itemType, id: itemID)
            } label: {
                Label(String(localized: toggle.actionTitle), systemImage: toggle.systemImage)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(toggle.isFavorite ? accent : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .help(Text(toggle.actionTitle))
            .accessibilityLabel(Text("Favorite"))
            .accessibilityValue(Text(toggle.accessibilityValue))
            .accessibilityHint(Text(toggle.actionTitle))
            .accessibilityAddTraits(toggle.isFavorite ? .isSelected : [])
        }
    }
}

/// Add to Favorites or Remove from Favorites for an album or artist menu. It reads the store
/// itself, so it stays right after the header's heart changes the item.
struct MacFavoriteMenuItem: View {
    let itemType: FavoriteType
    let itemID: String

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        FavoriteMatches(itemType, id: itemID) { toggle in
            Button(String(localized: toggle.actionTitle), systemImage: toggle.menuSystemImage) {
                playback.setFavorite(toggle.toggled, itemType: itemType, id: itemID)
            }
        }
    }
}

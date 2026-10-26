import CoreGraphics
import Foundation

// Hearts in Winamp mode. Only songs are starred: song stars are what the server passes on to
// Last.fm, ListenBrainz and Apple Music loves. Local files, the demo clip and radio have no
// server song to star.

/// The main window's heart for the song that's playing.
nonisolated struct WinampFavoriteStatus: Sendable, Hashable {
    /// The server song the heart is for; nil hides the heart.
    var songID: String?
    var isFavorite: Bool
    /// Starring needs the server; offline the heart shows its state but can't change it.
    var isOnline: Bool

    static let unavailable = WinampFavoriteStatus(songID: nil, isFavorite: false, isOnline: false)

    var isShown: Bool { songID != nil }
    var canToggle: Bool { songID != nil && isOnline }

    /// The heart for the current song: hidden for radio, local files and an empty player.
    static func current(songID: String?, isLocalFile: Bool, isRadio: Bool, isOnline: Bool,
                        isFavorite: (String) -> Bool) -> WinampFavoriteStatus {
        guard !isRadio, !isLocalFile, let songID, !songID.isEmpty, !songID.hasPrefix("local:") else { return .unavailable }
        return WinampFavoriteStatus(songID: songID, isFavorite: isFavorite(songID), isOnline: isOnline)
    }

    /// What View > Winamp and the main window's menu call the action.
    var menuTitle: LocalizedStringResource {
        isFavorite ? "Remove Current Song from Favorites" : "Add Current Song to Favorites"
    }
}

/// Starring several playlist rows at once, as the Music app does: if every chosen song is already
/// a favourite they're all unstarred, otherwise the ones that aren't yet are starred.
nonisolated enum WinampFavoriteSelection {
    enum Action: Sendable, Hashable {
        case star([String])
        case unstar([String])
    }

    /// One song in the selection: its ID and whether it's a local file.
    struct Song: Sendable, Hashable {
        let id: String
        let isLocalFile: Bool

        init(id: String, isLocalFile: Bool) {
            self.id = id
            self.isLocalFile = isLocalFile
        }
    }

    /// Server songs only, each once, in playlist order.
    static func serverSongIDs(_ songs: [Song]) -> [String] {
        var seen = Set<String>()
        return songs.compactMap { song in
            guard !song.isLocalFile, !song.id.hasPrefix("local:"), seen.insert(song.id).inserted else { return nil }
            return song.id
        }
    }

    /// Nil when nothing chosen can be starred.
    static func action(for songs: [Song], isFavorite: (String) -> Bool) -> Action? {
        let ids = serverSongIDs(songs)
        guard !ids.isEmpty else { return nil }
        let unstarred = ids.filter { !isFavorite($0) }
        return unstarred.isEmpty ? .unstar(ids) : .star(unstarred)
    }

    /// The menu item for the action.
    static func title(for action: Action?) -> LocalizedStringResource {
        if case .unstar = action { return "Remove from Favorites" }
        return "Add to Favorites"
    }
}

/// The heart drawn in the main window, in the gap between the kHz label and the mono and stereo
/// lights, the same height as the kbps and kHz text. Classic skins have no heart sprite, so it is
/// drawn pixel by pixel in the skin's text colour: hollow when the song isn't a favourite, solid
/// when it is.
nonisolated enum WinampHeart {
    static let width = 7
    static let height = 6

    /// Top-left of the heart in the 275×116 main window.
    static let origin = CGPoint(x: 196, y: 43)

    /// The area that takes clicks: the heart with a few pixels around it, still clear of the kHz
    /// box, the mono light and the title.
    static let hitArea = CGRect(x: 192, y: 40, width: 15, height: 12)

    private static let filledRows = [
        ".XX.XX.",
        "XXXXXXX",
        "XXXXXXX",
        ".XXXXX.",
        "..XXX..",
        "...X...",
    ]

    private static let outlineRows = [
        ".XX.XX.",
        "X..X..X",
        "X.....X",
        ".X...X.",
        "..X.X..",
        "...X...",
    ]

    /// The lit pixels, as offsets from the heart's top-left corner.
    static func pixels(filled: Bool) -> [CGPoint] {
        let rows = filled ? filledRows : outlineRows
        return rows.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, character in
                character == "X" ? CGPoint(x: x, y: y) : nil
            }
        }
    }
}

/// The colour a skin draws its text in, from `text.bmp`: the most common colour after the
/// background, which is the most common of all. The heart uses it so it reads like the kbps and
/// kHz digits beside it.
nonisolated enum WinampTextColor {
    static func of(_ skin: WinampSkin) -> WinampColor? {
        guard let sheet = skin.sheets[.text] else { return nil }
        return dominantForeground(in: sheet)
    }

    static func dominantForeground(in image: CGImage) -> WinampColor? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var counts: [WinampColor: Int] = [:]
        for index in 0..<(width * height) {
            let offset = index * 4
            guard bytes[offset + 3] > 0 else { continue }
            counts[WinampColor(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2]), default: 0] += 1
        }
        // Ties are broken by the colour's value so the answer doesn't depend on dictionary order.
        let ranked = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.sortKey < $1.key.sortKey
        }
        return ranked.count > 1 ? ranked[1].key : nil
    }
}

private extension WinampColor {
    nonisolated var sortKey: Int { Int(red) << 16 | Int(green) << 8 | Int(blue) }
}

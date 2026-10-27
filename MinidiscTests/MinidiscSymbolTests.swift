import SwiftUI
import Testing
import UIKit
@testable import Minidisc

/// The app's own symbols load from the asset catalog as symbol images, so they take weights,
/// scales and tints like system symbols.
@MainActor
struct MinidiscSymbolTests {
    @Test(arguments: [MinidiscSymbol.album, MinidiscSymbol.albumFill])
    func loadsAsASymbolImage(name: String) throws {
        let image = try #require(UIImage(named: name, in: Bundle(for: AppContainer.self), compatibleWith: nil))
        #expect(image.isSymbolImage)
        #expect(MinidiscSymbol.isCustom(name))
        #expect(UIImage.symbol(name)?.isSymbolImage == true)
    }

    @Test func takesWeightsAndScalesLikeASystemSymbol() throws {
        let base = try #require(UIImage.symbol(MinidiscSymbol.album))
        let regular = try #require(base.applyingSymbolConfiguration(.init(pointSize: 20, weight: .regular)))
        let black = try #require(base.applyingSymbolConfiguration(.init(pointSize: 20, weight: .black)))
        let large = try #require(base.applyingSymbolConfiguration(.init(pointSize: 20, weight: .regular, scale: .large)))
        #expect(black.size.width > regular.size.width)
        #expect(large.size.height > regular.size.height)
    }

    @Test func systemSymbolsStaySystemSymbols() {
        #expect(!MinidiscSymbol.isCustom("square.stack"))
        #expect(UIImage.symbol("music.note")?.isSymbolImage == true)
    }

    @Test func goToAlbumUsesTheMiniDisc() {
        #expect(MinidiscSymbol.goToAlbum == "minidisc")
        #expect(UIImage.symbol(MinidiscSymbol.goToAlbum)?.isSymbolImage == true)
    }

    /// Every Go to Album menu item, on the iPhone and the Mac, names the MiniDisc rather than a
    /// system symbol such as music.note.square.stack.
    @Test func everyGoToAlbumMenuItemNamesTheMiniDisc() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = [
            "Minidisc/DesignSystem/Components/SongRow.swift",
            "Minidisc/DesignSystem/Components/ItemContextMenus.swift",
            "Minidisc/Views/Main/FullPlayerView.swift",
            "MinidiscMac/Library/MacSongMenu.swift",
        ]
        for file in files {
            let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
            let labels = source.components(separatedBy: .newlines).filter { $0.contains("Label(\"Go to Album\"") }
            #expect(!labels.isEmpty, "\(file) has no Go to Album item")
            for line in labels {
                #expect(line.contains("MinidiscSymbol.goToAlbum"), "\(file): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }
}

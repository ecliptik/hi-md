import SwiftUI
import Testing
import UIKit
@testable import Minidisc

/// A song change on the player: the same cover changes nothing, another one cross-fades in once
/// it's ready, and the backdrop goes from one palette to the next without passing through black.
@Suite("Player artwork and backdrop across song changes")
@MainActor
struct PlayerArtworkChangeTests {
    // MARK: Artwork

    @Test func theSameCoverChangesNothing() {
        let image = solidImage(.red)
        let shown = ArtworkChange.Shown(coverID: "al-1", image: ObjectIdentifier(image))
        #expect(ArtworkChange.between(shown, shown, reduceMotion: false) == .none)
        #expect(ArtworkChange.between(shown, shown, reduceMotion: true) == .none)
    }

    @Test func anotherCoverCrossFadesOrSwapsWithReduceMotion() {
        // Held, so each image keeps its own identity for the comparison.
        let images = [solidImage(.red), solidImage(.blue), solidImage(.green)]
        let old = ArtworkChange.Shown(coverID: "mf-1", image: ObjectIdentifier(images[0]))
        let new = ArtworkChange.Shown(coverID: "mf-2", image: ObjectIdentifier(images[1]))
        #expect(ArtworkChange.between(old, new, reduceMotion: false) == .crossfade)
        #expect(ArtworkChange.between(old, new, reduceMotion: true) == .swap)
        // A sharper image under the same id fades in too.
        let sharper = ArtworkChange.Shown(coverID: "mf-1", image: ObjectIdentifier(images[2]))
        #expect(ArtworkChange.between(old, sharper, reduceMotion: false) == .crossfade)
        withExtendedLifetime(images) {}
    }

    @Test func theFirstImageAndTheSamePictureUnderAnotherIdSwapAtOnce() {
        let image = solidImage(.red)
        let first = ArtworkChange.Shown(coverID: "al-1", image: ObjectIdentifier(image))
        #expect(ArtworkChange.between(nil, first, reduceMotion: false) == .swap)
        let sameImage = ArtworkChange.Shown(coverID: "mf-9", image: ObjectIdentifier(image))
        #expect(ArtworkChange.between(first, sameImage, reduceMotion: false) == .swap)
        #expect(ArtworkChange.duration == 0.25)
    }

    // MARK: Backdrop

    @Test func theBackdropKeepsItsPaletteWhileTheNextCoversIsWorkedOut() {
        // A palette on screen stays; only the default black gives way to the new cover's average.
        #expect(FullPlayerViewModel.interimColors(showingPaletteOf: "al-1", average: .red) == nil)
        #expect(FullPlayerViewModel.interimColors(showingPaletteOf: nil, average: .red) == Array(repeating: .red, count: 4))
        // Never the default black in between.
        #expect(FullPlayerViewModel.interimColors(showingPaletteOf: nil, average: nil) == nil)
        #expect(FullPlayerViewModel.interimColors(showingPaletteOf: "al-1", average: nil) == nil)
    }

    @Test func aNewCoverWithoutColoursYetKeepsTheLastSongsPalette() async throws {
        let extractor = DominantColorExtractor()
        let first = "test-\(UUID().uuidString)"
        let second = "test-\(UUID().uuidString)"
        defer {
            extractor.invalidate(for: first)
            extractor.invalidate(for: second)
        }
        let palette = try #require(await extractor.backgroundColors(for: first, image: solidImage(.red)))
        let model = FullPlayerViewModel()
        await model.updateColors(for: first, colorExtractor: extractor, container: nil, reduceMotion: true)
        #expect(model.backgroundColors == palette)
        #expect(model.paletteID == first)

        // Nothing is known about the next cover yet: the backdrop doesn't flash black.
        await model.updateColors(for: second, colorExtractor: extractor, container: nil, reduceMotion: true)
        #expect(model.coverArtID == second)
        #expect(model.backgroundColors == palette)
        // And a view drawing the next cover keeps the model's colours rather than guessing.
        #expect(model.displayedColors(for: second, colorExtractor: extractor) == palette)
    }

    @Test func theSameCoverAgainLeavesTheBackdropAlone() async throws {
        let extractor = DominantColorExtractor()
        let id = "test-\(UUID().uuidString)"
        defer { extractor.invalidate(for: id) }
        let palette = try #require(await extractor.backgroundColors(for: id, image: solidImage(.blue)))
        let model = FullPlayerViewModel()
        await model.updateColors(for: id, colorExtractor: extractor, container: nil, reduceMotion: true)
        await model.updateColors(for: id, colorExtractor: extractor, container: nil, reduceMotion: true)
        #expect(model.backgroundColors == palette)
        #expect(model.paletteID == id)
    }

    @Test func beforeAnyPaletteTheFirstFrameUsesTheCoversMemoizedColours() async throws {
        let extractor = DominantColorExtractor()
        let id = "test-\(UUID().uuidString)"
        defer { extractor.invalidate(for: id) }
        let palette = try #require(await extractor.backgroundColors(for: id, image: solidImage(.green)))
        let model = FullPlayerViewModel()
        #expect(model.displayedColors(for: id, colorExtractor: extractor) == palette)
        // Nothing playing: the default.
        await model.updateColors(for: nil, colorExtractor: extractor, container: nil, reduceMotion: true)
        #expect(model.backgroundColors == FullPlayerViewModel.defaultColors)
        #expect(model.paletteID == nil)
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }
}

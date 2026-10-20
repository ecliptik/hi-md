import Foundation
import OSLog
import UIKit

/// Writes small cover thumbnails into the App Group for widgets and Live Activities.
@MainActor
final class WidgetArtworkWriter {
    private let artworkImageCache: ArtworkImageCache
    private static let maxPixels: CGFloat = 240

    init(artworkImageCache: ArtworkImageCache) {
        self.artworkImageCache = artworkImageCache
    }

    /// Returns the thumbnail's file name, writing it first when it is missing.
    func file(for coverArtId: String?) async -> String? {
        guard let coverArtId, let directory = WidgetSnapshotStore.artworkDirectory else { return nil }
        let name = WidgetSnapshotStore.artworkFileName(coverArtId: coverArtId)
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        guard let image = await artworkImageCache.load(coverArtId: coverArtId, tier: .thumb),
              let data = Self.thumbnail(image).jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            Logger.ui.debug("Could not write widget artwork: \(error, privacy: .public)")
            return nil
        }
    }

    /// Removes thumbnails the snapshot no longer references.
    func prune(keeping files: Set<String>) {
        guard let directory = WidgetSnapshotStore.artworkDirectory,
              let existing = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in existing where !files.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func thumbnail(_ image: UIImage) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxPixels else { return image }
        let scale = maxPixels / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

import SwiftUI
import UIKit

/// Lidarr covers seen this session. Bounded and costed by decoded size, so a long browse can't
/// hold every cover it has shown; NSCache also drops entries under memory pressure.
@MainActor
final class LidarrImageStore {
    static let shared = LidarrImageStore()
    static let countLimit = 120
    static let costLimit = 48 * 1_048_576
    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = LidarrImageStore.countLimit
        cache.totalCostLimit = LidarrImageStore.costLimit
        return cache
    }()

    func image(for key: String) -> UIImage? { images.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) {
        images.setObject(image, forKey: key as NSString, cost: image.decodedByteCount)
    }
    func removeAll() { images.removeAllObjects() }
}

struct LidarrCoverImage<Placeholder: View>: View {
    let path: String?
    let client: LidarrClient
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        image = nil
        guard let path else { return }
        if let cached = LidarrImageStore.shared.image(for: path) {
            image = cached
            return
        }
        guard let data = try? await client.imageData(forPath: path),
              let loaded = UIImage(data: data) else { return }
        LidarrImageStore.shared.store(loaded, for: path)
        image = loaded
    }
}

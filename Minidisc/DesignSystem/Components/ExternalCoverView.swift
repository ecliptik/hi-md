import SwiftUI

/// Drop-in replacement for `AsyncImage` that routes external cover URLs through
/// `ExternalArtworkCache` (memory → disk → network) instead of hitting the network
/// on every render. Use inside a fixed-size container; the image fills its parent.
///
/// `placeholder` shows while the cover loads. With `showsDiscWhenMissing` (album covers), a cover
/// that turns out to be missing (no URL, or the load failed) shows the MiniDisc instead.
struct ExternalCoverView<Placeholder: View>: View {
    let url: URL?
    var showsDiscWhenMissing = false
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.appContainer) private var container
    @State private var image: PlatformImage?
    @State private var missingURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else if showsDiscWhenMissing, url == nil || missingURL == url {
                MissingCoverDisc()
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            guard let requestedURL = url, let cache = container?.externalArtworkCache else { return }
            let loadedImage = await cache.image(for: requestedURL)
            guard !Task.isCancelled, requestedURL == url else { return }
            if loadedImage == nil, await cache.isMissing(requestedURL) {
                guard !Task.isCancelled, requestedURL == url else { return }
                withAnimation(CoverArtView.arrival) { missingURL = requestedURL }
                return
            }
            image = loadedImage
        }
    }
}

import SwiftUI

enum PlaylistDownloadControl {
    case download, downloadMissing, cancel, remove

    var symbol: String {
        switch self {
        case .download, .downloadMissing: "arrow.down"
        case .cancel: "xmark"
        case .remove: "checkmark"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .download: "Download Playlist"
        case .downloadMissing: "Download Missing Tracks"
        case .cancel: "Cancel Download"
        case .remove: "Remove Download"
        }
    }
}

struct PlaylistPlaybackControls: View {
    let isEnabled: Bool
    let songs: [DisplayableSong]
    /// The Play capsule's fill and label, and the shuffle icon's colour.
    let playFill: Color
    let playLabel: Color
    let shuffleColor: Color
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .callout) private var scaledControlSize: CGFloat = 48
    @ScaledMetric(relativeTo: .callout) private var scaledPlayWidth: CGFloat = 160

    private var controlSize: CGFloat { min(scaledControlSize, 64) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: MinidiscSpacing.l))
            : AnyLayout(HStackLayout(spacing: MinidiscSpacing.l))

        layout {
            Button(action: onShuffle) {
                Image(systemName: "shuffle")
                    .font(.minidiscCellTitle)
                    .foregroundStyle(shuffleColor)
                    .frame(width: controlSize, height: controlSize)
                    .background(.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Shuffle")
            .accessibilityIdentifier("playlist.detail.shuffle")

            PlayMenuButton(songs: songs, fillColor: playFill, labelColor: playLabel,
                           height: dynamicTypeSize.isAccessibilitySize ? nil : controlSize, onPlay: onPlay)
                .frame(maxWidth: scaledPlayWidth + 60)
                .accessibilityIdentifier("playlist.detail.play")
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MinidiscSpacing.xxl)
    }
}

import SwiftUI

/// The Play capsule on album and playlist screens. Tapping it plays from the start; the chevron at
/// its trailing end is its own button, opening Play Next and Add to Queue.
struct PlayMenuButton: View {
    let songs: [DisplayableSong]
    var fillColor: Color
    var labelColor: Color
    var height: CGFloat? = 48
    /// Where Play says the queue came from.
    var context: PlaybackContext? = nil
    /// Replaces the default "play from the first song", e.g. to apply a sort order.
    var onPlay: (() -> Void)? = nil

    @Environment(\.appContainer) private var container

    /// The chevron's tap target, at least 44 points wide.
    private static let menuWidth: CGFloat = 52

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: play) {
                HStack(spacing: MinidiscSpacing.s) {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .padding(.vertical, height == nil ? MinidiscSpacing.m : 0)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    Task { await container?.playerService.playNext(songs) }
                }
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
                    Task { await container?.playerService.addToQueue(songs) }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .frame(width: Self.menuWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More Play Options")
        }
        .font(.minidiscCellTitle)
        .foregroundStyle(labelColor)
        .fixedSize(horizontal: false, vertical: true)
        .background(songs.isEmpty ? fillColor.opacity(0.4) : fillColor, in: Capsule())
        .disabled(songs.isEmpty)
    }

    private func play() {
        HapticFeedback.medium.trigger()
        if let onPlay { return onPlay() }
        let songs = songs
        let context = context
        Task {
            await container?.toastService.perform {
                try await container?.playerService.play(tracks: songs, startIndex: 0, context: context)
            }
        }
    }
}

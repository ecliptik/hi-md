import SwiftUI

/// The Play capsule on album and playlist screens. Tapping plays from the start; the chevron
/// marks a menu, opened by touching and holding, with Play Next and Add to Queue.
struct PlayMenuButton: View {
    let songs: [DisplayableSong]
    var fillColor: Color
    var labelColor: Color
    var height: CGFloat = 48

    @Environment(\.appContainer) private var container

    var body: some View {
        Menu {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Task { await container?.playerService.playNext(songs) }
            }
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
                Task { await container?.playerService.addToQueue(songs) }
            }
        } label: {
            HStack(spacing: MinidiscSpacing.s) {
                Image(systemName: "play.fill")
                Text("Play")
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.minidiscCellTitle)
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(songs.isEmpty ? fillColor.opacity(0.4) : fillColor, in: Capsule())
            .contentShape(Capsule())
        } primaryAction: {
            HapticFeedback.medium.trigger()
            let songs = songs
            Task { await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: 0) } }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(songs.isEmpty)
        .accessibilityHint("Touch and hold for Play Next and Add to Queue.")
    }
}

import SwiftUI

/// A minimal transport bar: the playing song, Play/Pause and Next, driven by the shared player.
struct MacPlayerBar: View {
    let container: AppContainer

    private var playerState: PlayerState { container.playerState }

    var body: some View {
        HStack(spacing: 12) {
            if let track = playerState.currentTrack {
                CoverArtView(id: track.coverArtId ?? track.id, size: 36, cornerRadius: 4)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Not Playing")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await container.playerService.togglePlayPause() }
            } label: {
                Image(systemName: playerState.wantsPlayback ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .accessibilityLabel(playerState.wantsPlayback ? "Pause" : "Play")
            .disabled(playerState.currentTrack == nil)

            Button {
                Task { await container.toastService.perform { try await container.playerService.skipToNext() } }
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("Next Track")
            .disabled(playerState.queue.isEmpty)
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

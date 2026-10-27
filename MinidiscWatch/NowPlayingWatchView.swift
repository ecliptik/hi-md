import SwiftUI
import UIKit

/// The watch's main screen: the phone's current song with play/pause, skip and favourite, and a
/// link to the Mood playlists.
struct NowPlayingWatchView: View {
    let session: WatchSessionModel

    private var state: WatchNowPlaying { session.nowPlaying }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if state.hasTrack {
                    artwork
                    VStack(spacing: 2) {
                        Text(state.title ?? "").font(.headline).lineLimit(2).multilineTextAlignment(.center)
                        Text(state.artist ?? "").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    controls
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("Play something in Hi-MD on your iPhone.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                if !state.moods.isEmpty {
                    NavigationLink {
                        MoodsWatchView(session: session)
                    } label: {
                        Label("Moods", systemImage: "sparkles")
                    }
                    .padding(.top, 4)
                }
                if !session.isReachable {
                    Text("iPhone not reachable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Hi-MD")
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = state.artwork, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { session.send(.previous) } label: { Image(systemName: "backward.fill") }
                .disabled(!state.canSkip)
                .accessibilityLabel("Previous")
            Button { session.send(.togglePlayPause) } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            Button { session.send(.next) } label: { Image(systemName: "forward.fill") }
                .disabled(!state.canSkip)
                .accessibilityLabel("Next")
            Button { session.send(.toggleFavorite) } label: {
                Image(systemName: state.isFavorite ? "heart.fill" : "heart")
            }
            .disabled(!state.canFavorite)
            .accessibilityLabel(state.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .buttonStyle(.bordered)
        .disabled(!session.isReachable)
    }
}

struct MoodsWatchView: View {
    let session: WatchSessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(session.nowPlaying.moods) { mood in
            Button {
                session.send(.playMood(mood.id))
                dismiss()
            } label: {
                Label(mood.title, systemImage: mood.symbolName)
            }
        }
        .navigationTitle("Moods")
    }
}

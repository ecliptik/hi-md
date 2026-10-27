import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowPlaying", provider: SnapshotProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("The song that is playing, with play, pause and next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

private struct NowPlayingWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let track = entry.snapshot.nowPlaying {
            switch family {
            case .accessoryCircular:
                Button(intent: ToggleMinidiscPlaybackIntent()) {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).font(.caption).lineLimit(1)
                    controls(track, size: .caption)
                }
            case .systemMedium:
                HStack(spacing: 12) {
                    WidgetArtwork(file: track.artworkFile, showsDisc: true).aspectRatio(1, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.headline).lineLimit(2)
                        Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        controls(track, size: .title2)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    WidgetArtwork(file: track.artworkFile, showsDisc: true).frame(width: 56, height: 56)
                    Spacer(minLength: 0)
                    Text(track.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    controls(track, size: .body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WidgetEmptyMessage(text: entry.snapshot.hasServer ? "Nothing is playing" : "Open Hi-MD to connect")
        }
    }

    private func controls(_ track: WidgetSnapshot.Track, size: Font) -> some View {
        HStack(spacing: 16) {
            Button(intent: ToggleMinidiscPlaybackIntent()) {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(track.isPlaying ? Text("Pause") : Text("Play"))
            Button(intent: SkipMinidiscTrackIntent()) {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel(Text("Next Track"))
        }
        .font(size)
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

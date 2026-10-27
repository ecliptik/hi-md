import SwiftUI
import UIKit
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Every widget reads the same snapshot. The app reloads timelines when it changes, so no
/// widget refreshes on a schedule.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshotStore.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.load() ?? WidgetSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        hasServer: true,
        nowPlaying: Track(title: "Song Title", artist: "Artist", artworkFile: nil, isPlaying: true),
        recentlyPlayed: (1...8).map { Collection(id: "\($0)", kind: .album, title: "Album \($0)", subtitle: "Artist") },
        pinned: (1...4).map { Collection(id: "p\($0)", kind: .playlist, title: "Playlist \($0)") },
        moods: [
            MoodEntry(id: "night", title: "Night", symbolName: "moon.stars", isAvailable: true),
            MoodEntry(id: "energetic", title: "Energetic", symbolName: "bolt", isAvailable: true),
            MoodEntry(id: "workout", title: "Workout", symbolName: "figure.run", isAvailable: true),
            MoodEntry(id: "chill", title: "Chill", symbolName: "leaf", isAvailable: true),
            MoodEntry(id: "focus", title: "Focus", symbolName: "headphones", isAvailable: true),
        ]
    )
}

/// A cover from the App Group, or a placeholder. Decorative: every use sits beside, or inside a
/// link named after, the title it shows.
struct WidgetArtwork: View {
    let file: String?
    var cornerRadius: CGFloat = 8
    /// Albums, songs and playlists without a cover show the MiniDisc, as they do in the app. The
    /// app writes a snapshot only after loading its covers, so a missing file is a missing cover.
    var showsDisc = false

    var body: some View {
        Group {
            if let url = WidgetSnapshotStore.artworkURL(file), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if showsDisc {
                ZStack {
                    Color.secondary.opacity(0.2)
                    Image("MinidiscLogoThumb")
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(0.84)
                }
            } else {
                ZStack {
                    Color.secondary.opacity(0.2)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Shown when no server is configured or nothing is available yet.
struct WidgetEmptyMessage: View {
    let text: LocalizedStringResource

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "opticaldisc").font(.title2).foregroundStyle(.tint)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

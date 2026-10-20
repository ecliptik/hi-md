import AppIntents
import SwiftUI
import WidgetKit

struct RecentlyPlayedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentlyPlayed", provider: SnapshotProvider()) { entry in
            CollectionGrid(items: entry.snapshot.recentlyPlayed, title: "Recently Played", hasServer: entry.snapshot.hasServer, showsPlayButton: false)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recently Played")
        .description("Albums you played recently.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait])
    }
}

struct PinnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Pinned", provider: SnapshotProvider()) { entry in
            CollectionGrid(items: entry.snapshot.pinned, title: "Pinned", hasServer: entry.snapshot.hasServer, showsPlayButton: true)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned")
        .description("Your pinned albums and playlists.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Covers that open their album or playlist, optionally with a play button on each.
private struct CollectionGrid: View {
    let items: [WidgetSnapshot.Collection]
    let title: LocalizedStringResource
    let hasServer: Bool
    let showsPlayButton: Bool
    @Environment(\.widgetFamily) private var family

    private var columns: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 4
        case .systemExtraLarge: 6
        default: 3
        }
    }

    private var limit: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        case .systemLarge: 9
        case .systemExtraLargePortrait: 12
        default: 12
        }
    }

    var body: some View {
        if items.isEmpty {
            WidgetEmptyMessage(text: hasServer ? "Nothing here yet" : "Open Minidisc to connect")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if family != .systemSmall {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(items.prefix(limit)) { item in
                        Link(destination: item.url) {
                            cell(item)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cell(_ item: WidgetSnapshot.Collection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetArtwork(file: item.artworkFile, cornerRadius: item.kind == .artist ? 100 : 8)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if showsPlayButton {
                        Button(intent: PlayMinidiscCollectionIntent(kind: item.kind.rawValue, id: item.id)) {
                            Image(systemName: "play.circle.fill").font(.title3).symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .tint)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(Text("Play \(item.title)"))
                    }
                }
            if family != .systemSmall && family != .systemMedium {
                Text(item.title).font(.caption2).lineLimit(1)
            }
        }
    }
}

struct MoodsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Moods", provider: SnapshotProvider()) { entry in
            MoodsView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Moods")
        .description("Play one of your Mood playlists.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct MoodsView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let moods = snapshot.moods.filter(\.isAvailable)
        if moods.isEmpty {
            WidgetEmptyMessage(text: snapshot.hasServer ? "Create Mood playlists in Minidisc" : "Open Minidisc to connect")
        } else {
            let shown = Array(moods.prefix(family == .systemSmall ? 4 : 6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: family == .systemSmall ? 2 : 3), spacing: 8) {
                ForEach(shown) { mood in
                    if let value = MinidiscMood(rawValue: mood.id) {
                        Button(intent: PlayMinidiscMoodWidgetIntent(mood: value)) {
                            VStack(spacing: 4) {
                                Image(systemName: mood.symbolName).font(.title3)
                                Text(mood.title).font(.caption2).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }
                }
            }
        }
    }
}

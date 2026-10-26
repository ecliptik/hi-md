import SwiftUI

/// The player's "Playing from" line: the source's symbol and name, e.g. "DJ Shadow Station".
/// Opens the album, playlist or artist when the source is one; otherwise it is plain text.
struct PlaybackContextLabel: View {
    let context: PlaybackContext
    /// The player's secondary text colour, which stays at or above 4.5:1 on its backdrop.
    let color: Color
    var isOnline = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Artists open from the server, so offline the line stays plain; albums and playlists also
    /// open from downloads.
    private var destination: PlaybackContext.Destination? {
        guard let destination = context.destination else { return nil }
        if case .artist = destination, !isOnline { return nil }
        return destination
    }

    var body: some View {
        if let destination {
            Button {
                HapticFeedback.light.trigger()
                open(destination)
            } label: {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(context.accessibilityLabel)
            .accessibilityIdentifier("player.playingFrom")
        } else {
            content(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(context.accessibilityLabel)
                .accessibilityIdentifier("player.playingFrom")
        }
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(spacing: MinidiscSpacing.xs) {
            Image(systemName: context.symbolName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(context.title)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .frame(minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func open(_ destination: PlaybackContext.Destination) {
        switch destination {
        case .artist(let id, let name):
            postNavigateToArtist(artistId: id, artistName: name, coverArtId: nil)
        case .album(let id, let name, let coverArtId):
            postNavigateToAlbum(albumId: id, albumName: name, coverArtId: coverArtId)
        case .playlist(let id, let name, let coverArtId):
            postNavigateToPlaylist(playlistId: id, name: name, coverArtId: coverArtId)
        }
    }
}

/// The queue's header naming the source: "Playing Next from DJ Shadow Station".
struct PlaybackContextQueueHeader: View {
    let context: PlaybackContext
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MinidiscSpacing.xs) {
            Image(systemName: context.symbolName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(context.queueHeader)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("queue.playingFrom")
    }
}

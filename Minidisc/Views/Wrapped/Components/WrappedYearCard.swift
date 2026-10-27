import OSLog
import SwiftUI

struct WrappedYearCard: View {
    let year: Int
    let firstTrack: TopTrackEntry?
    let lastTrack: TopTrackEntry?
    let playlistId: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var yearString: String { String(year) }

    var body: some View {
        Group {
            if let pid = playlistId {
                NavigationLink {
                    PlaylistDetailView(
                        playlistId: pid,
                        name: "Minidisc Wrapped \(yearString)"
                    )
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    Logger.wrapped.debug("[WRAPPED-YEAR-CARD] tapped year=\(year, privacy: .public) playlistId=\(pid, privacy: .public)")
                })
            } else {
                // Unavailable years read as muted through grayscale alone: fading the card to 70%
                // let the page show through and took its white text to 2.7:1 in light mode.
                cardContent
                    .grayscale(0.8)
            }
        }
    }

    private var cardContent: some View {
        let palette = WrappedYearPalette.colors(for: year)
        return MeshGradientBackground(palette: palette, animated: !reduceMotion)
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .overlay { overlayContent }
            .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.hero, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Hi-MD Wrapped")
                    .scaledFont(size: 22, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                Spacer()
                if playlistId != nil {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 14)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                }
            }

            Spacer()

            Text(yearString)
                .scaledFont(size: 140, weight: .black, design: .rounded)
                .kerning(-4)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)

            subtitleView
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                .lineLimit(2)
                .padding(.top, MinidiscSpacing.xs)
        }
        .padding(MinidiscSpacing.l)
    }

    @ViewBuilder
    private var subtitleView: some View {
        if playlistId == nil {
            Text("No playlist generated yet")
        } else if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            Text("Started with \(first.title) · Ended with \(last.title)")
        } else if let first = firstTrack {
            Text("Your year started with \(first.title)")
        } else {
            Text("Hi-MD Wrapped \(yearString)")
        }
    }

    private var accessibilityLabel: String {
        var label = "Hi-MD Wrapped \(yearString)"
        if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            label += ". Started with \(first.title), ended with \(last.title)"
        } else if let first = firstTrack {
            label += ". Your year started with \(first.title)"
        }
        label += playlistId != nil ? ". Tap to open playlist." : "."
        return label
    }
}

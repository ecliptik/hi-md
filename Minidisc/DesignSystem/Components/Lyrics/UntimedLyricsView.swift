import SwiftSonic
import SwiftUI

/// The spacing of untimed lyrics for a text size: normal leading within a stanza, about a line's
/// height between stanzas, and a small note above them.
nonisolated struct UntimedLyricsMetrics: Equatable, Sendable {
    /// The lyrics' point size, after Dynamic Type.
    let textSize: Double

    /// Extra leading between the lines of a stanza.
    var lineSpacing: Double { (textSize * 0.3).rounded() }
    /// The gap between stanzas, and between the note and the first stanza.
    var stanzaSpacing: Double { (textSize * 1.1).rounded() }
    /// The note's point size: a little under the lyrics', 12 to 17 points.
    var noteSize: Double { min(max((textSize * 0.8).rounded(), 12), 17) }
}

/// The colours untimed lyrics are drawn in.
nonisolated enum UntimedLyricsPalette {
    /// The note's white over the player backdrops: 4.5:1 on the brightest stop any of them
    /// allows (the player's secondary text).
    static let noteOpacity = PlayerBackgroundPalette.secondaryOpacity
}

/// Lyrics without timings, laid out to read rather than to follow, as the Music app shows them:
/// "Lyrics aren't timed for this song" in small secondary text first, then the words in regular
/// weight at a reading size, left-aligned, every line alike, stanzas kept apart. The listener
/// scrolls freely; nothing follows the song, highlights a line or seeks on a tap.
struct UntimedLyricsView: View {
    private let stanzas: [String]
    private let note: LocalizedStringResource?
    private let pointSize: Double
    private let scalesWithDynamicType: Bool
    private let usesSystemColors: Bool
    private let insets: EdgeInsets

    @ScaledMetric private var dynamicTypeScale: Double

    /// - Parameters:
    ///   - pointSize: The lyrics' size at the default Dynamic Type size.
    ///   - textStyle: The text style Dynamic Type scales `pointSize` like, when it scales.
    ///   - scalesWithDynamicType: Whether the size follows Dynamic Type (the iPhone), or stays
    ///     at `pointSize` (the Mac's panes, which size the lyrics to the window).
    init(lines: [Line], note: LocalizedStringResource?, pointSize: Double,
         textStyle: Font.TextStyle = .body, scalesWithDynamicType: Bool,
         usesSystemColors: Bool = false, insets: EdgeInsets) {
        stanzas = LyricsTiming.stanzas(from: lines.map(\.value))
        self.note = note
        self.pointSize = pointSize
        self.scalesWithDynamicType = scalesWithDynamicType
        self.usesSystemColors = usesSystemColors
        self.insets = insets
        _dynamicTypeScale = ScaledMetric(wrappedValue: 1, relativeTo: textStyle)
    }

    private var metrics: UntimedLyricsMetrics {
        UntimedLyricsMetrics(textSize: pointSize * (scalesWithDynamicType ? dynamicTypeScale : 1))
    }

    private var primary: AnyShapeStyle {
        usesSystemColors ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white)
    }

    private var secondary: AnyShapeStyle {
        usesSystemColors ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white.opacity(UntimedLyricsPalette.noteOpacity))
    }

    var body: some View {
        let metrics = metrics
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.stanzaSpacing) {
                if let note {
                    Label {
                        Text(note)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: metrics.noteSize))
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(stanzas.enumerated()), id: \.offset) { _, stanza in
                    Text(stanza)
                        .font(.system(size: metrics.textSize))
                        .lineSpacing(metrics.lineSpacing)
                        .foregroundStyle(primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .padding(insets)
        }
        // The Mac shows its scroller as the listener scrolls; the iPhone's player keeps it hidden.
        #if os(macOS)
        .scrollIndicators(.automatic)
        #else
        .scrollIndicators(.hidden)
        #endif
    }
}

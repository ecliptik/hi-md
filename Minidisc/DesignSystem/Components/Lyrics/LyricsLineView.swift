import SwiftUI

struct LyricsLineView: View {
    let value: String
    let index: Int
    let currentIndex: Int?
    let isSynced: Bool
    let isTappable: Bool
    let onTap: () -> Void
    /// Centred, larger lines for the full-screen karaoke view.
    var isKaraoke = false

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var blurRadius: CGFloat {
        guard isSynced, currentIndex != nil else { return 0 }
        switch distance {
        case 0: return 0
        case 1: return 1.5
        case 2: return 3.5
        default: return 6
        }
    }

    private var opacity: Double {
        guard isSynced, currentIndex != nil else { return 1.0 }
        switch distance {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.4
        default: return 0.25
        }
    }

    private var scale: CGFloat {
        guard isSynced, currentIndex != nil else { return 1.0 }
        return distance == 0 ? 1.05 : 1.0
    }

    private var lineFont: Font {
        isKaraoke ? .system(.largeTitle, design: .rounded, weight: .heavy) : .system(.title, design: .rounded, weight: .bold)
    }

    var body: some View {
        Text(value)
            .font(lineFont)
            .multilineTextAlignment(isKaraoke ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: isKaraoke ? .center : .leading)
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: blurRadius)
            .scaleEffect(isKaraoke && distance == 0 && currentIndex != nil ? 1.12 : scale,
                         anchor: isKaraoke ? .center : .leading)
            .animation(.easeInOut(duration: 0.25), value: currentIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
    }
}

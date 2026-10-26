import SwiftUI

enum MacShelfMetrics {
    /// How many cards a shelf shows; the heading opens the rest.
    static let previewLimit = 20
    static let albumSide: CGFloat = 160
    static let playlistSide: CGFloat = 200
    static let cardSpacing: CGFloat = 18
    static let margin: CGFloat = 20
}

/// A Home or Discover shelf, like the Music app's: a heading, which opens the full list when
/// there is one, and a row of cards that scrolls sideways. Back and forward buttons page through
/// it with a mouse; a trackpad swipes.
struct MacShelf<Content: View>: View {
    let title: String
    /// Opens the full list. Nil for a shelf that shows everything already.
    var onOpen: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var metrics = ScrollMetrics()

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var visible: CGFloat = 0
        var total: CGFloat = 0

        var canGoBack: Bool { offset > 1 }
        var canGoForward: Bool { offset + visible < total - 1 }
        var overflows: Bool { total > visible + 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MacShelfHeading(title: title, onOpen: onOpen)
                Spacer(minLength: 12)
                if metrics.overflows {
                    pagingButtons
                }
            }
            .padding(.horizontal, MacShelfMetrics.margin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: MacShelfMetrics.cardSpacing) {
                    content()
                }
                .padding(.horizontal, MacShelfMetrics.margin)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(offset: geometry.contentOffset.x, visible: geometry.containerSize.width,
                              total: geometry.contentSize.width)
            } action: { _, new in
                metrics = new
            }
        }
    }

    private var pagingButtons: some View {
        HStack(spacing: 2) {
            Button("Scroll Back", systemImage: "chevron.backward") { page(by: -1) }
                .disabled(!metrics.canGoBack)
                .help("Scroll Back")
            Button("Scroll Forward", systemImage: "chevron.forward") { page(by: 1) }
                .disabled(!metrics.canGoForward)
                .help("Scroll Forward")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    /// Moves most of a window's width, so the last card stays in view as a landmark.
    private func page(by direction: CGFloat) {
        let step = max(metrics.visible - MacShelfMetrics.margin * 2, 100) * direction
        let target = min(max(0, metrics.offset + step), max(0, metrics.total - metrics.visible))
        withAnimation(.smooth(duration: 0.35)) { position.scrollTo(x: target) }
    }
}

/// A shelf's title. With somewhere to go it's a button with a chevron, as in the Music app.
struct MacShelfHeading: View {
    let title: String
    var onOpen: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        if let onOpen {
            Button(action: onOpen) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: title)
                        .font(.title2.bold())
                    Image(systemName: "chevron.forward")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isHovering ? .primary : .secondary)
                        .accessibilityHidden(true)
                }
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("See All")
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityHint("See All")
            .accessibilityAddTraits(.isHeader)
        } else {
            Text(verbatim: title)
                .font(.title2.bold())
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Holds a loading shelf's place with grey cards the size of the real ones, so the shelves below
/// don't move when it arrives.
struct MacShelfPlaceholder: View {
    let title: String
    var side: CGFloat = MacShelfMetrics.albumSide
    var count = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacShelfHeading(title: title)
                .padding(.horizontal, MacShelfMetrics.margin)
            HStack(alignment: .top, spacing: MacShelfMetrics.cardSpacing) {
                ForEach(0..<count, id: \.self) { _ in
                    MacCardPlaceholder(side: side)
                }
            }
            .padding(.horizontal, MacShelfMetrics.margin)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue("Loading…")
    }
}

/// A card's square and two lines of text, greyed out.
struct MacCardPlaceholder: View {
    let side: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: side, height: side, cornerRadius: 6)
            SkeletonBlock(width: side * 0.7, height: 11)
            SkeletonBlock(width: side * 0.45, height: 10)
        }
        .frame(width: side, alignment: .leading)
    }
}

/// The round play button shown over a cover while the pointer is on it.
struct MacHoverPlayButton: View {
    var label: LocalizedStringKey = "Play"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Lifts a card slightly while the pointer is on it.
struct MacCardHover: ViewModifier {
    @Binding var isHovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion ? 1.02 : 1, anchor: .bottom)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }
    }
}

extension View {
    func macCardHover(_ isHovering: Binding<Bool>) -> some View {
        modifier(MacCardHover(isHovering: isHovering))
    }
}

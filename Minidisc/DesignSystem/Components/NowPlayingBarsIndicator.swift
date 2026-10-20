import SwiftUI

struct NowPlayingBarsIndicator: View {
    let isPlaying: Bool

    @Environment(\.minidiscPlayingAccent) private var playingAccent
    @Environment(\.systemPrefersReducedResourceUsage) private var prefersReducedResourceUsage
    private let delays: [Double] = [0.0, 0.15, 0.30]
    @State private var heights: [CGFloat] = [4, 8, 4]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(playingAccent)
                    .frame(width: 3, height: heights[i])
            }
        }
        .frame(width: 14, height: 14, alignment: .center)
        .onAppear { if isPlaying { startAnimating() } }
        .onChange(of: isPlaying) { _, playing in
            if playing { startAnimating() } else { stopAnimating() }
        }
        .onChange(of: prefersReducedResourceUsage) {
            if isPlaying { startAnimating() }
        }
    }

    private func startAnimating() {
        // Still bars when iOS asks apps to save resources; they still read as "playing".
        guard !prefersReducedResourceUsage else {
            withTransaction(Transaction(animation: nil)) { heights = [6, 12, 8] }
            return
        }
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.45)
                .repeatForever(autoreverses: true)
                .delay(delays[i])
            ) {
                heights[i] = i == 1 ? 14 : 10
            }
        }
    }

    private func stopAnimating() {
        withAnimation(.easeInOut(duration: 0.2)) {
            heights = [3, 3, 3]
        }
    }
}

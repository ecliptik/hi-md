import SwiftUI

struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 6) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(reduceMotion ? 0.08 : (isPulsing ? 0.10 : 0.05)))
            .frame(width: width, height: height)
            .onAppear { updatePulse() }
            .onChange(of: reduceMotion) { updatePulse() }
    }

    /// Pulses unless Reduce Motion is on, when the block holds a steady midpoint shade.
    private func updatePulse() {
        guard !reduceMotion else {
            // A non-animated change replaces the repeating animation.
            withTransaction(Transaction(animation: nil)) { isPulsing = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

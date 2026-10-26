import SwiftUI

struct EmptyStateView: View {
    struct Action {
        let label: LocalizedStringKey
        let handler: () -> Void
    }

    let systemImage: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var action: Action? = nil
    /// The icon and subtitle. Views over artwork pass a colour tuned for their backdrop, since the
    /// system secondary falls under 4.5:1 there.
    var secondaryStyle = AnyShapeStyle(.secondary)

    var body: some View {
        VStack(spacing: MinidiscSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(secondaryStyle)

            VStack(spacing: MinidiscSpacing.s) {
                Text(title)
                    .font(.minidiscSectionTitle)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.minidiscBody)
                        .foregroundStyle(secondaryStyle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }

            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.minidiscAccent)
            }
        }
        .padding(MinidiscSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("With action") {
    EmptyStateView(
        systemImage: "magnifyingglass",
        title: "No Results",
        subtitle: "Try another category or search term.",
        action: .init(label: "Clear") {}
    )
}

#Preview("Minimal") {
    EmptyStateView(systemImage: "arrow.down.circle", title: "No Downloads")
        .preferredColorScheme(.dark)
}

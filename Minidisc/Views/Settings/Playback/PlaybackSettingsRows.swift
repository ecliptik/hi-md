import SwiftUI

/// A settings row's title with a short explanation underneath.
struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A navigation row: title and explanation on the leading side, the current choice trailing.
/// The value stays beside the title; at accessibility text sizes it moves underneath.
struct SettingsValueRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let value: Text

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: MinidiscSpacing.m))
        layout {
            SettingsRowLabel(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            value
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// One choice in a single-choice list. The selected row shows a checkmark and is announced as
/// selected.
struct SettingsChoiceRow: View {
    let title: Text
    var subtitle: Text?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: MinidiscSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .foregroundStyle(.primary)
                    if let subtitle {
                        subtitle
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: MinidiscSpacing.s)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MinidiscColors.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

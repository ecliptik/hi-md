import SwiftUI

/// A header button's label: icon and title, or the icon alone when the window is too narrow for
/// the whole row. The title stays the accessibility label either way.
struct MacHeaderLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            Label(configuration)
                .labelStyle(.iconOnly)
        } else {
            Label(configuration)
        }
    }
}

extension View {
    /// The button's title as a help tag once its label shows only the icon.
    @ViewBuilder
    func macHeaderHelp(_ title: LocalizedStringKey, compact: Bool) -> some View {
        if compact { help(title) } else { self }
    }
}

import SwiftUI

/// The lists' sort button, one glass toolbar button with the Music app's menu: the fields with a
/// checkmark on the current one, a divider, then Ascending and Descending.
struct MacSortMenu<Field: LibrarySortField>: View {
    @Binding var order: LibrarySortOrder<Field>
    /// The fields this list offers, in the menu's order.
    var fields: [Field] = Array(Field.allCases)

    var body: some View {
        Menu {
            ForEach(fields, id: \.self) { field in
                Toggle(isOn: Binding(get: { order.field == field }, set: { isOn in
                    if isOn { order.select(field) }
                })) {
                    Text(field.title)
                }
            }
            Divider()
            ForEach(SortDirection.allCases, id: \.self) { direction in
                Toggle(isOn: Binding(get: { order.direction == direction }, set: { isOn in
                    if isOn { order.direction = direction }
                })) {
                    Text(direction.title)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuIndicator(.hidden)
        .help("Sort")
        .accessibilityValue(Text(verbatim: "\(String(localized: order.field.title)), \(String(localized: order.direction.title))"))
    }
}

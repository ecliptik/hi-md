import Foundation

/// The Add Music browser's search: narrows the folder on screen (artists, then albums, then songs
/// as you drill down) to the names that contain what's typed. Case, accents and full- or
/// half-width forms are ignored, as `localizedStandardContains` does, so "beyonce" finds
/// "Beyoncé" and "ｱﾗﾝ" finds "アラン"; Japanese and Chinese names match as typed.
///
/// Every name is folded once when the listing arrives, so typing into a folder of thousands of
/// artists only compares strings.
nonisolated struct MusicFolderFilter: Sendable {
    let items: [MusicFolderItem]
    private let keys: [String]
    private let locale: Locale

    init(items: [MusicFolderItem], locale: Locale = .current) {
        self.items = items
        self.locale = locale
        keys = items.map { Self.fold($0.name, locale: locale) }
    }

    /// The items whose names contain every word of `query`, in listing order. A blank query keeps
    /// them all.
    func matches(_ query: String) -> [MusicFolderItem] {
        let words = Self.words(in: query, locale: locale)
        guard !words.isEmpty else { return items }
        return zip(items, keys).compactMap { item, key in
            words.allSatisfy { key.contains($0) } ? item : nil
        }
    }

    /// The query's words, folded the same way as the names.
    static func words(in query: String, locale: Locale = .current) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0), locale: locale) }
    }

    static func isActive(_ query: String) -> Bool {
        query.contains { !$0.isWhitespace }
    }

    static func fold(_ text: String, locale: Locale = .current) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }

    // MARK: Acting on the filtered list

    /// What Play and Add take: the selected rows that are shown, or every shown row when nothing
    /// is selected. A selection of only rows that aren't items (such as "..") takes nothing.
    static func chosen(from shown: [MusicFolderItem], selection: Set<String>) -> [MusicFolderItem] {
        selection.isEmpty ? shown : shown.filter { selection.contains($0.id) }
    }

    /// What Return in the search field opens: the selection when it's on screen, otherwise the
    /// first match. Nil when nothing is shown.
    static func returnTarget(shown: [MusicFolderItem], selection: Set<String>) -> Set<String>? {
        let selected = Set(shown.map(\.id)).intersection(selection)
        if !selected.isEmpty { return selected }
        return shown.first.map { [$0.id] }
    }

    /// The row the arrow keys move to from the search field, through `rowIDs` in screen order:
    /// down from the last selected row or up from the first, stopping at the ends. With nothing
    /// selected, down starts at the top and up at the bottom.
    static func movedSelection(rowIDs: [String], selection: Set<String>, by delta: Int) -> String? {
        guard !rowIDs.isEmpty, delta != 0 else { return nil }
        let selectedIndices = rowIDs.indices.filter { selection.contains(rowIDs[$0]) }
        guard let anchor = delta > 0 ? selectedIndices.last : selectedIndices.first else {
            return delta > 0 ? rowIDs.first : rowIDs.last
        }
        return rowIDs[min(max(anchor + delta, 0), rowIDs.count - 1)]
    }
}

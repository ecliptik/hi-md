import Foundation

/// The search of the browsers that narrow a list as you type: Winamp mode's Add Music (artists,
/// then albums, then songs as you drill down its folders) and the Mac MiniPlayer's Library. Keeps
/// the names that contain what's typed. Case, accents and full- or half-width forms are ignored,
/// as `localizedStandardContains` does, so "beyonce" finds "Beyoncé" and "ｱﾗﾝ" finds "アラン";
/// Japanese and Chinese names match as typed.
///
/// Every name is folded once when the listing arrives, so typing into a folder of thousands of
/// artists only compares strings.
nonisolated struct LibraryNameFilter<Item: Identifiable & Sendable>: Sendable where Item.ID == String {
    let items: [Item]
    private let keys: [String]
    private let locale: Locale

    init(items: [Item], locale: Locale = .current, name: (Item) -> String) {
        self.items = items
        self.locale = locale
        keys = items.map { LibraryFilterText.fold(name($0), locale: locale) }
    }

    /// The items whose names contain every word of `query`, in listing order. A blank query keeps
    /// them all.
    func matches(_ query: String) -> [Item] {
        let words = LibraryFilterText.words(in: query, locale: locale)
        guard !words.isEmpty else { return items }
        return zip(items, keys).compactMap { item, key in
            words.allSatisfy { key.contains($0) } ? item : nil
        }
    }

    // MARK: Acting on the filtered list

    /// What Play and Add take: the selected rows that are shown, or every shown row when nothing
    /// is selected. A selection of only rows that aren't items (such as "..") takes nothing.
    static func chosen(from shown: [Item], selection: Set<String>) -> [Item] {
        selection.isEmpty ? shown : shown.filter { selection.contains($0.id) }
    }

    /// What Return in the search field opens: the selection when it's on screen, otherwise the
    /// first match. Nil when nothing is shown.
    static func returnTarget(shown: [Item], selection: Set<String>) -> Set<String>? {
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

/// How the browsers' search compares text.
nonisolated enum LibraryFilterText {
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
}

/// A listing and what its search field leaves of it: the query, the filter built once from the
/// listing, and the items shown. Both browsers keep one per folder or page on screen.
nonisolated struct FilteredListing<Item: Identifiable & Sendable>: Sendable where Item.ID == String {
    private(set) var filter: LibraryNameFilter<Item>
    /// The items the search leaves, in listing order.
    private(set) var shown: [Item]
    private var queryText = ""

    init(items: [Item] = [], locale: Locale = .current, name: (Item) -> String) {
        filter = LibraryNameFilter(items: items, locale: locale, name: name)
        shown = items
    }

    var items: [Item] { filter.items }

    /// The search field: narrows the list as it's typed into.
    var query: String {
        get { queryText }
        set {
            queryText = newValue
            shown = filter.matches(newValue)
        }
    }

    var isFiltering: Bool { LibraryFilterText.isActive(queryText) }

    /// The search found nothing in a list that has something.
    var hasNoMatches: Bool { isFiltering && shown.isEmpty && !items.isEmpty }
}

/// Winamp mode's Add Music browser search, over one music folder.
typealias MusicFolderFilter = LibraryNameFilter<MusicFolderItem>

nonisolated extension LibraryNameFilter where Item == MusicFolderItem {
    init(items: [MusicFolderItem], locale: Locale = .current) {
        self.init(items: items, locale: locale, name: \.name)
    }

    /// The query's words, folded the same way as the names.
    static func words(in query: String, locale: Locale = .current) -> [String] {
        LibraryFilterText.words(in: query, locale: locale)
    }

    static func isActive(_ query: String) -> Bool {
        LibraryFilterText.isActive(query)
    }

    static func fold(_ text: String, locale: Locale = .current) -> String {
        LibraryFilterText.fold(text, locale: locale)
    }
}

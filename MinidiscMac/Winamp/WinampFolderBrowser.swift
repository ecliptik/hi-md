import AppKit
import OSLog
import SwiftSonic
import SwiftUI

/// Winamp mode's Eject: the server's music folders listed like a file system. Double-click a
/// folder to open it and ".." to go back up. Play replaces the queue with the selection and Add
/// appends it; folders bring every song beneath them, up to the browser's limits. The search
/// field (⌘F) narrows the folder on screen; Escape clears it, Return opens the first match, and
/// each folder opened starts unfiltered.
@Observable
final class WinampFolderBrowserModel {
    struct Row: Identifiable, Hashable {
        enum Kind: Hashable {
            case parent(MusicFolderLocation)
            case item(MusicFolderItem)
        }

        let id: String
        let kind: Kind
    }

    static let parentRowID = ".."

    private(set) var listing: MusicFolderListing?
    private(set) var isLoading = false
    private(set) var isQueueing = false
    private(set) var errorMessage: String?
    private(set) var notice: String?
    var selection: Set<Row.ID> = []
    /// The folder's items and what the search leaves of them; shared with the MiniPlayer's
    /// Library browser.
    private var filtered = FilteredListing<MusicFolderItem>(name: \.name)

    /// The rows the search leaves, in listing order. ".." isn't among them; it always shows.
    var shownItems: [MusicFolderItem] { filtered.shown }

    /// The search field: narrows the folder on screen as it's typed into. Each folder opened
    /// starts with it empty.
    var query: String {
        get { filtered.query }
        set {
            filtered.query = newValue
            pruneSelection()
        }
    }

    var isFiltering: Bool { filtered.isFiltering }

    /// The search found nothing in a folder that has something.
    var hasNoMatches: Bool { filtered.hasNoMatches }

    @ObservationIgnored private let browser: MusicFolderBrowser
    @ObservationIgnored private let playerService: any PlayerServiceProtocol
    @ObservationIgnored private let toastService: ToastService
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var lastRequested: MusicFolderLocation = .libraries
    @ObservationIgnored var onFinished: () -> Void = {}

    init(container: AppContainer) {
        browser = MusicFolderBrowser(source: WinampSubsonicSource(serverService: container.serverService))
        playerService = container.playerService
        toastService = container.toastService
    }

    /// ".." first whenever there's a folder above, then the rows the search leaves.
    var rows: [Row] {
        guard let listing else { return [] }
        var rows: [Row] = []
        if let parent = listing.parent {
            rows.append(Row(id: Self.parentRowID, kind: .parent(parent)))
        }
        rows += shownItems.map { Row(id: $0.id, kind: .item($0)) }
        return rows
    }

    /// Rows the search hides drop out of the selection, so Play and Add take only what's shown.
    private func pruneSelection() {
        let visible = Set(shownItems.map(\.id)).union([Self.parentRowID])
        let kept = selection.intersection(visible)
        if kept != selection { selection = kept }
    }

    private func show(_ listing: MusicFolderListing) {
        self.listing = listing
        filtered = FilteredListing(items: listing.items, name: \.name)
        selection = []
    }

    func clearQuery() {
        query = ""
    }

    /// Return in the search field: opens the selected row, or the first match.
    func submitSearch() {
        guard let target = MusicFolderFilter.returnTarget(shown: shownItems, selection: selection) else { return }
        activate(target)
    }

    /// Up and down arrows typed in the search field move the list's selection.
    func moveSelection(by delta: Int) {
        guard let id = MusicFolderFilter.movedSelection(rowIDs: rows.map(\.id), selection: selection, by: delta) else { return }
        selection = [id]
    }

    /// The folder's name, or "Server" at the top.
    var title: String {
        guard let listing, !listing.name.isEmpty else { return String(localized: "Server") }
        return listing.name
    }

    /// Play and Add need a selection, or a folder below the list of libraries to take whole.
    var canQueue: Bool {
        guard let listing, !isQueueing else { return false }
        let picked = chosenItems(in: listing)
        return !picked.isEmpty && (!selection.isEmpty || listing.location != .libraries)
    }

    func start() {
        guard listing == nil, loadTask == nil else { return }
        load(.libraries, enterSingleLibrary: true)
    }

    func retry() {
        load(lastRequested)
    }

    func load(_ location: MusicFolderLocation, enterSingleLibrary: Bool = false) {
        loadTask?.cancel()
        lastRequested = location
        isLoading = true
        errorMessage = nil
        notice = nil
        loadTask = Task { [weak self, browser] in
            do {
                var listing = try await browser.listing(at: location)
                // A server with one library opens straight into it.
                if enterSingleLibrary, listing.location == .libraries, listing.folders.count == 1,
                   let only = listing.folders.first?.folder {
                    listing = try await browser.listing(at: only)
                }
                guard !Task.isCancelled else { return }
                self?.show(listing)
            } catch {
                guard !Task.isCancelled else { return }
                Logger.ui.error("Winamp: folder listing failed: \(String(describing: error), privacy: .public)")
                self?.errorMessage = MusicFolderBrowserError.message(for: error)
            }
            self?.isLoading = false
            self?.loadTask = nil
        }
    }

    /// Double-click or Return: open a folder or "..", or play the selected songs.
    func activate(_ ids: Set<Row.ID>) {
        let picked = rows.filter { ids.contains($0.id) }
        if picked.count == 1, let row = picked.first {
            switch row.kind {
            case .parent(let parent):
                load(parent)
                return
            case .item(let item):
                if let folder = item.folder {
                    load(folder)
                    return
                }
            }
        }
        selection = ids
        queue(replacing: true)
    }

    /// Play replaces the queue; Add appends to it.
    func queue(replacing: Bool) {
        guard let listing, canQueue else { return }
        let items = chosenItems(in: listing)
        isQueueing = true
        notice = nil
        Task { [weak self, browser, playerService, toastService] in
            var songs: [Song] = []
            var truncated = false
            let limit = MusicFolderBrowser.defaultSongLimit
            let collected = await toastService.perform {
                for item in items {
                    guard songs.count < limit else {
                        truncated = true
                        break
                    }
                    switch item.kind {
                    case .song(let song):
                        songs.append(song)
                    case .folder(let location):
                        let found = try await browser.allSongs(under: location, songLimit: limit - songs.count)
                        songs += found.songs
                        truncated = truncated || found.isTruncated
                    }
                }
            }
            let tracks = songs.map { DisplayableSong(from: $0) }
            if collected, !tracks.isEmpty {
                if replacing {
                    _ = await toastService.perform { try await playerService.play(tracks: tracks, startIndex: 0) }
                } else {
                    await playerService.appendToQueue(tracks)
                }
            }
            guard let self else { return }
            isQueueing = false
            if truncated {
                notice = String(localized: "Only the first \(tracks.count) songs were added.")
            } else if collected {
                onFinished()
            }
        }
    }

    /// The selected rows, or every row the search leaves when nothing is selected. ".." never counts.
    private func chosenItems(in listing: MusicFolderListing) -> [MusicFolderItem] {
        MusicFolderFilter.chosen(from: shownItems, selection: selection)
    }
}

struct WinampFolderBrowserView: View {
    @Bindable var model: WinampFolderBrowserModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(verbatim: model.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if model.isLoading || model.isQueueing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            Divider()
            content
            Divider()
            HStack {
                if let notice = model.notice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Add") { model.queue(replacing: false) }
                    .disabled(!model.canQueue)
                Button("Play") { model.queue(replacing: true) }
                    // While typing, Return opens the first match instead.
                    .keyboardShortcut(isSearchFocused ? nil : .defaultAction)
                    .disabled(!model.canQueue)
            }
            .padding(12)
        }
        .frame(minWidth: 360, minHeight: 320)
        .background {
            // ⌘F puts the cursor in the search field.
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onExitCommand {
            if !model.query.isEmpty { model.clearQuery() }
        }
        .task { model.start() }
    }

    /// Narrows the folder on screen, matching folder and song names as they're typed.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $model.query, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { model.submitSearch() }
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !model.query.isEmpty else { return .ignored }
                    model.clearQuery()
                    return .handled
                }
            if !model.query.isEmpty {
                Button {
                    model.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .help("Clear")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var content: some View {
        if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { model.retry() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.rows, selection: $model.selection) { row in
                WinampFolderRow(row: row)
            }
            .contextMenu(forSelectionType: WinampFolderBrowserModel.Row.ID.self) { _ in
            } primaryAction: { ids in
                model.activate(ids)
            }
            .overlay {
                // ".." stays above, so the way back up is still there.
                if model.hasNoMatches {
                    ContentUnavailableView.search(text: model.query)
                }
            }
            .disabled(model.isQueueing)
        }
    }
}

private struct WinampFolderRow: View {
    let row: WinampFolderBrowserModel.Row

    var body: some View {
        switch row.kind {
        case .parent:
            Label {
                Text(verbatim: "..")
            } icon: {
                Image(systemName: "arrow.turn.left.up")
            }
        case .item(let item):
            HStack {
                Label {
                    Text(verbatim: item.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: item.folder == nil ? "music.note" : "folder.fill")
                        .foregroundStyle(item.folder == nil ? Color.secondary : Color.accentColor)
                }
                Spacer()
                if let duration = item.song?.duration, duration > 0 {
                    Text(verbatim: WinampMarquee.clock(duration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The browser's own small titled window, opened from Eject.
final class WinampFolderBrowserWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let model: WinampFolderBrowserModel

    init(container: AppContainer) {
        model = WinampFolderBrowserModel(container: container)
        let hosting = NSHostingController(rootView: WinampFolderBrowserView(model: model))
        window = NSWindow(contentViewController: hosting)
        super.init()
        window.title = String(localized: "Add Music")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(CGSize(width: 440, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        // Restores the size and place it had last time, when there is one.
        window.setFrameAutosaveName("WinampFolderBrowser")
        model.onFinished = { [weak self] in self?.window.performClose(nil) }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }
}

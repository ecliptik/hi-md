import AppKit
import Observation
import OSLog

/// Drives the Winamp playlist window: the play queue drawn from `pledit.bmp` in the skin's
/// colours, with selection, double-click to play, drag to reorder, Delete to remove, the skinned
/// scroll bar, the +ADD / −REM / SEL / MISC / LIST menus, resizing in Winamp's steps and
/// windowshade.
///
/// Queue edits go through PlayerService's selection-checked move and remove, one song at a time,
/// as `UpNextClearing` does: each re-prepares the gapless or crossfade transition only if the next
/// song changed, and a request made against a queue that changed meanwhile is refused.
final class WinampPlaylistWindowController: NSObject, NSWindowDelegate, WinampSurfaceDelegate, WinampManagedWindow {
    private enum Interaction {
        case button(WinampPlaylistControl)
        case windowDrag
        /// A press on selected rows: dragging moves them; releasing without a move selects the row.
        case rows(anchor: Int, clickRow: Int?, moved: Bool)
        case scroll(grab: CGFloat)
        case resize(mouse: NSPoint, start: CGSize)
        case menu(WinampPlaylistMenuKind)
    }

    let kind = WinampPreferences.Window.playlist
    let window: WinampWindow
    private let view: WinampSurfaceView
    private let container: AppContainer
    private weak var host: WinampWindowHost?
    private let preferences: WinampPreferences
    private var skin: WinampSkin
    private var sprites: WinampSpriteCache
    private var size: WinampPlaylistSize
    private var isShaded: Bool
    private var isActive = false
    private var isObserving = false

    private var selection = WinampPlaylistSelection()
    private var firstRow = 0
    private var pressed: WinampPlaylistControl?
    private var interaction: Interaction?
    private var openMenu: WinampPlaylistMenuKind?
    private var highlightedItem: WinampPlaylistMenuItem?
    /// Whether the pointer has left the menu's button since it opened.
    private var menuWasEntered = false
    private var lastGeneration: UInt64?

    // Reordering: rows moved so far in this drag, and where the pointer wants them.
    private var reorderApplied = 0
    private var reorderTarget = 0
    private var reorderTask: Task<Void, Never>?
    private var editTask: Task<Void, Never>?

    private var player: PlayerState { container.playerState }

    init(container: AppContainer, skin: WinampSkin, host: WinampWindowHost) {
        self.container = container
        self.host = host
        preferences = host.preferences
        self.skin = skin
        sprites = WinampSpriteCache(skin: skin)
        size = host.preferences.playlistSize
        isShaded = host.preferences.isShaded(.playlist) && WinampPlaylistRenderer.hasShadeSprites(skin)
        view = WinampSurfaceView(logicalSize: size.pixelSize, accessibilityLabel: String(localized: "Miniamp Playlist"))
        window = WinampWindow(contentSize: size.pixelSize)
        super.init()
        window.title = String(localized: "Miniamp Playlist")
        window.contentView = view
        window.delegate = self
        window.closeHandler = { [weak host] in host?.close(.playlist) }
        view.delegate = self
        view.logicalSize = logicalSize
    }

    var logicalSize: CGSize { isShaded ? WinampPlaylistLayout.shadeSize(width: size.pixelSize.width) : size.pixelSize }
    private var scale: CGFloat { host?.scale ?? 1 }
    private var visibleRows: Int { WinampPlaylistLayout.visibleRows(in: size.pixelSize) }

    // MARK: WinampManagedWindow

    func show(at topLeft: CGPoint) {
        let pixels = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        window.setFrame(CGRect(x: topLeft.x, y: topLeft.y - pixels.height, width: pixels.width, height: pixels.height), display: true)
        isObserving = true
        lastGeneration = player.queueGeneration
        firstRow = WinampPlaylistScroll.firstRow(showing: player.currentIndex, current: 0,
                                                 count: player.queue.count, visible: visibleRows)
        observePlayer()
        window.orderFront(nil)
    }

    func tearDown() {
        isObserving = false
        reorderTask?.cancel()
        editTask?.cancel()
        window.delegate = nil
        window.orderOut(nil)
    }

    func setSkin(_ skin: WinampSkin) {
        self.skin = skin
        sprites = WinampSpriteCache(skin: skin)
        if isShaded, !WinampPlaylistRenderer.hasShadeSprites(skin) { toggleShade() }
        refresh()
    }

    func refresh() {
        view.logicalSize = logicalSize
        view.refresh()
    }

    // MARK: Player observation

    private func observePlayer() {
        guard isObserving else { return }
        withObservationTracking {
            _ = player.queue
            _ = player.currentIndex
            _ = player.originalQueueEndIndex
            _ = player.currentTrack?.id
            _ = player.position
            _ = player.duration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.playerDidChange() }
        }
    }

    private func playerDidChange() {
        guard isObserving else { return }
        if player.queueGeneration != lastGeneration {
            // A new queue: the old selection means nothing in it.
            lastGeneration = player.queueGeneration
            selection = WinampPlaylistSelection()
            firstRow = WinampPlaylistScroll.firstRow(showing: player.currentIndex, current: 0,
                                                     count: player.queue.count, visible: visibleRows)
        }
        selection.clamp(count: player.queue.count)
        firstRow = WinampPlaylistScroll.clampedFirstRow(firstRow, count: player.queue.count, visible: visibleRows)
        refresh()
        observePlayer()
    }

    // MARK: Display

    private var currentRow: Int? {
        player.currentTrack != nil && player.queue.indices.contains(player.currentIndex) ? player.currentIndex : nil
    }

    private var displayState: WinampPlaylistDisplayState {
        var state = WinampPlaylistDisplayState()
        let queue = player.queue
        state.size = size.pixelSize
        state.isActive = isActive
        state.isShaded = isShaded
        state.totalRows = queue.count
        state.firstRow = firstRow
        let current = currentRow
        let end = min(firstRow + visibleRows + 1, queue.count)
        // Songs Autoplay added after the listener's own, set apart rather than mixed in.
        let autoplayStart = player.originalQueueEndIndex.flatMap { $0 < queue.count ? $0 : nil }
        if firstRow < end {
            state.rows = (firstRow..<end).map { index in
                let song = queue[index]
                return .init(title: WinampPlaylistText.rowTitle(number: index + 1, artist: song.artist, title: song.title),
                             duration: WinampPlaylistText.duration(song.duration),
                             isSelected: selection.contains(index), isCurrent: index == current,
                             isAutoplay: autoplayStart.map { index >= $0 } ?? false,
                             startsAutoplay: index == autoplayStart && index > 0)
            }
        }
        state.focusedRow = isActive ? selection.focus : nil
        let durations = queue.map(\.duration)
        let selected = selection.rows.sorted().compactMap { durations.indices.contains($0) ? durations[$0] : nil }
        state.runningTime = WinampPlaylistText.runningTime(selected: selected, total: durations)
        if let current {
            state.miniTime = WinampPlaylistText.miniTime(position: player.position, duration: player.duration, mode: preferences.timeMode)
            let song = queue[current]
            state.shadeTitle = WinampPlaylistText.rowTitle(number: current + 1, artist: song.artist, title: song.title)
        }
        state.pressed = pressed
        state.openMenu = openMenu
        state.highlightedMenuItem = highlightedItem
        return state
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        isActive = true
        refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        isActive = false
        if openMenu != nil { closeMenu() }
        refresh()
    }

    // MARK: Mouse

    func surfaceImage(_ view: WinampSurfaceView, pixelScale: CGFloat) -> CGImage? {
        WinampPlaylistRenderer.render(displayState, skin: skin, sprites: sprites, scale: pixelScale)
    }

    private func control(at point: CGPoint) -> WinampPlaylistControl? {
        isShaded ? WinampPlaylistLayout.shadeControl(at: point, width: size.pixelSize.width)
            : WinampPlaylistLayout.control(at: point, in: size.pixelSize)
    }

    func surface(_ view: WinampSurfaceView, mouseDownAt point: CGPoint, event: NSEvent) {
        if let kind = openMenu {
            // A menu left open by a click on its button: this click picks an item or closes it.
            let item = WinampPlaylistLayout.menuItem(at: point, in: kind, size: size.pixelSize)
            closeMenu()
            if let item { perform(item) }
            return
        }
        guard let control = control(at: point) else { return }
        switch control {
        case .titleBar:
            if event.clickCount == 2 {
                toggleShade()
            } else {
                interaction = .windowDrag
                host?.beginDrag(.playlist)
            }
        case .list:
            listMouseDown(at: point, event: event)
        case .scrollBar:
            scrollMouseDown(at: point)
        case .resize:
            interaction = .resize(mouse: NSEvent.mouseLocation, start: size.pixelSize)
        case .menu(let kind):
            openMenu = kind
            highlightedItem = nil
            menuWasEntered = false
            interaction = .menu(kind)
            refresh()
        case .close, .shade, .mini:
            interaction = .button(control)
            pressed = control
            refresh()
        case .footer:
            break
        }
    }

    func surface(_ view: WinampSurfaceView, mouseDraggedTo point: CGPoint, event: NSEvent) {
        switch interaction {
        case .windowDrag:
            host?.continueDrag()
        case .rows(let anchor, let clickRow, _):
            autoscroll(toward: point)
            let row = WinampPlaylistScroll.clampedRow(at: point.y, firstRow: firstRow, count: player.queue.count, size: size.pixelSize)
            guard row - anchor != reorderTarget else { return }
            interaction = .rows(anchor: anchor, clickRow: clickRow, moved: true)
            requestReorder(to: row - anchor)
        case .scroll(let grab):
            let track = WinampPlaylistLayout.scrollTrack(in: size.pixelSize)
            firstRow = WinampPlaylistScroll.firstRow(forThumbOffset: point.y - track.minY - grab, count: player.queue.count,
                                                     visible: visibleRows, trackHeight: track.height)
            refresh()
        case .resize(let mouse, let start):
            let location = NSEvent.mouseLocation
            let proposed = CGSize(width: start.width + (location.x - mouse.x) / scale,
                                  height: start.height - (location.y - mouse.y) / scale)
            let fitted = WinampPlaylistSize.fitting(proposed)
            guard fitted != size else { return }
            size = fitted
            preferences.playlistSize = fitted
            firstRow = WinampPlaylistScroll.clampedFirstRow(firstRow, count: player.queue.count, visible: visibleRows)
            view.logicalSize = logicalSize
            host?.resize(.playlist, to: CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale))
            refresh()
        case .menu(let kind):
            let item = WinampPlaylistLayout.menuItem(at: point, in: kind, size: size.pixelSize)
            let button = WinampPlaylistLayout.menuButton(kind, in: size.pixelSize)
            if !button.contains(point) { menuWasEntered = true }
            let highlighted = menuWasEntered ? item : nil
            if highlighted != highlightedItem {
                highlightedItem = highlighted
                refresh()
            }
        case .button(let control):
            let inside = self.control(at: point) == control
            if (pressed != nil) != inside {
                pressed = inside ? control : nil
                refresh()
            }
        case nil:
            break
        }
    }

    func surface(_ view: WinampSurfaceView, mouseUpAt point: CGPoint, event: NSEvent) {
        let finished = interaction
        interaction = nil
        switch finished {
        case .windowDrag:
            host?.endDrag()
        case .rows(_, let clickRow, let moved):
            // Moves still on their way finish: the rows end up where they were dropped.
            if !moved, let clickRow {
                selection.click(clickRow)
                refresh()
            }
        case .scroll:
            pressed = nil
            refresh()
        case .resize:
            break
        case .menu:
            // Released on an item after moving to it: that item. Released without moving, the
            // menu stays open for the next click, as its last item covers the button.
            if let item = highlightedItem {
                closeMenu()
                perform(item)
            } else if !menuWasEntered {
                refresh()
            } else {
                closeMenu()
            }
        case .button(let control):
            pressed = nil
            refresh()
            if self.control(at: point) == control { perform(control) }
        case nil:
            break
        }
    }

    func surface(_ view: WinampSurfaceView, scrollWheel event: NSEvent) {
        guard !isShaded else { return }
        let rows = event.hasPreciseScrollingDeltas ? -event.scrollingDeltaY / WinampPlaylistLayout.rowHeight : -event.scrollingDeltaY * 3
        guard abs(rows) >= 0.5 else { return }
        firstRow = WinampPlaylistScroll.clampedFirstRow(firstRow + Int(rows.rounded()), count: player.queue.count, visible: visibleRows)
        refresh()
    }

    func surface(_ view: WinampSurfaceView, menuAt point: CGPoint) -> NSMenu? {
        guard !isShaded, control(at: point) == .list else { return nil }
        if let row = WinampPlaylistScroll.row(at: point, firstRow: firstRow, count: player.queue.count, size: size.pixelSize),
           !selection.contains(row) {
            selection.click(row)
            refresh()
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let hasSelection = !selection.rows.isEmpty
        menu.addItem(winampMenuItem(String(localized: "Play"), isEnabled: selection.focus != nil) { [weak self] in
            guard let self, let focus = self.selection.focus else { return }
            self.play(row: focus)
        })
        menu.addItem(winampMenuItem(String(localized: "Remove from Playlist"), isEnabled: hasSelection) { [weak self] in
            self?.removeSelected()
        })
        menu.addItem(winampMenuItem(String(localized: "File Info…"), isEnabled: hasSelection) { [weak self] in self?.showInfo() })
        menu.addItem(favoriteSelectionItem())
        menu.addItem(.separator())
        addFileItems(to: menu)
        return menu
    }

    private var selectedSongs: [DisplayableSong] {
        let queue = player.queue
        return selection.rows.sorted().compactMap { queue.indices.contains($0) ? queue[$0] : nil }
    }

    /// Add to or Remove from Favorites for the selected songs: all removed when every one is a
    /// favourite already, otherwise the rest are added. Local files are left out.
    private func favoriteSelectionItem() -> NSMenuItem {
        let favorites = host?.favorites
        let action = favorites?.action(for: selectedSongs)
        return winampMenuItem(String(localized: WinampFavoriteSelection.title(for: action)),
                              isEnabled: action != nil && favorites?.canChange == true) {
            if let action { favorites?.apply(action) }
        }
    }

    private func listMouseDown(at point: CGPoint, event: NSEvent) {
        guard let row = WinampPlaylistScroll.row(at: point, firstRow: firstRow, count: player.queue.count, size: size.pixelSize) else {
            selection.selectNone()
            refresh()
            return
        }
        let flags = event.modifierFlags
        if event.clickCount == 2, !flags.contains(.shift), !flags.contains(.command) {
            selection.click(row)
            play(row: row)
            refresh()
            return
        }
        if flags.contains(.shift) {
            selection.click(row, extending: true)
        } else if flags.contains(.command) {
            selection.click(row, toggling: true)
        } else {
            let wasSelected = selection.contains(row)
            if !wasSelected { selection.click(row) }
            reorderApplied = 0
            reorderTarget = 0
            interaction = .rows(anchor: row, clickRow: wasSelected ? row : nil, moved: false)
        }
        refresh()
    }

    private func scrollMouseDown(at point: CGPoint) {
        let track = WinampPlaylistLayout.scrollTrack(in: size.pixelSize)
        let count = player.queue.count
        let offset = WinampPlaylistScroll.thumbOffset(firstRow: firstRow, count: count, visible: visibleRows, trackHeight: track.height)
        let thumbTop = track.minY + offset
        if point.y >= thumbTop, point.y < thumbTop + WinampPlaylistScroll.thumbHeight {
            interaction = .scroll(grab: point.y - thumbTop)
            pressed = .scrollBar
        } else {
            // A click in the groove pages towards it.
            let page = max(visibleRows - 1, 1)
            firstRow = WinampPlaylistScroll.clampedFirstRow(firstRow + (point.y < thumbTop ? -page : page),
                                                            count: count, visible: visibleRows)
        }
        refresh()
    }

    /// Dragging rows past the top or bottom of the list scrolls it.
    private func autoscroll(toward point: CGPoint) {
        let list = WinampPlaylistLayout.list(in: size.pixelSize)
        let step = point.y < list.minY ? -1 : point.y > list.maxY ? 1 : 0
        guard step != 0 else { return }
        firstRow = WinampPlaylistScroll.clampedFirstRow(firstRow + step, count: player.queue.count, visible: visibleRows)
        refresh()
    }

    private func closeMenu() {
        openMenu = nil
        highlightedItem = nil
        refresh()
    }

    // MARK: Keyboard

    func surface(_ view: WinampSurfaceView, keyDown event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let count = player.queue.count
        switch event.keyCode {
        case 125, 126: // down, up
            let delta = event.keyCode == 125 ? 1 : -1
            if flags.contains(.option) {
                shiftSelection(by: delta)
            } else {
                selection.moveFocus(by: delta, count: count, extending: flags.contains(.shift))
                revealFocus()
            }
            return true
        case 116, 121: // page up, page down
            selection.moveFocus(by: (event.keyCode == 121 ? 1 : -1) * max(visibleRows - 1, 1), count: count,
                                extending: flags.contains(.shift))
            revealFocus()
            return true
        case 115, 119: // home, end
            selection.moveFocus(by: event.keyCode == 119 ? count : -count, count: count, extending: flags.contains(.shift))
            revealFocus()
            return true
        case 36, 76: // return, enter
            if let focus = selection.focus { play(row: focus) }
            return true
        case 51, 117: // delete, forward delete
            removeSelected()
            return true
        default:
            break
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if flags == .command, key == "a" {
            selection.selectAll(count: count)
            refresh()
            return true
        }
        guard flags.isEmpty || flags == .shift else { return false }
        // Winamp's transport keys along the bottom row of the keyboard work in every window.
        let button: WinampPlaylistMiniButton? = switch key {
        case "z": .previous
        case "x": .play
        case "c": .pause
        case "v": .stop
        case "b": .next
        case "l": .eject
        default: nil
        }
        guard let button else { return false }
        perform(.mini(button))
        return true
    }

    private func revealFocus() {
        if let focus = selection.focus {
            firstRow = WinampPlaylistScroll.firstRow(showing: focus, current: firstRow, count: player.queue.count, visible: visibleRows)
        }
        refresh()
    }

    // MARK: Actions

    private func perform(_ control: WinampPlaylistControl) {
        switch control {
        case .close:
            host?.close(.playlist)
        case .shade:
            toggleShade()
        case .mini(let button):
            host?.performTransport(button)
        case .titleBar, .list, .scrollBar, .resize, .menu, .footer:
            break
        }
    }

    private func toggleShade() {
        guard WinampPlaylistRenderer.hasShadeSprites(skin) || isShaded else { return }
        isShaded.toggle()
        preferences.setShaded(isShaded, .playlist)
        view.logicalSize = logicalSize
        host?.resize(.playlist, to: CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale))
        refresh()
    }

    /// Double-click: plays that song, or restarts it if it's the one playing.
    private func play(row: Int) {
        let service = container.playerService
        if row == currentRow {
            Task {
                await service.seek(to: 0)
                await service.resume()
            }
            return
        }
        let state = player
        guard state.queue.indices.contains(row) else { return }
        if let selection = QueueTrackSelection(playerState: state, destinationIndex: row, destinationTrackID: state.queue[row].id) {
            Task { await container.toastService.perform { _ = try await service.selectQueueTrack(selection) } }
        } else {
            // Nothing loaded yet: start the queue at this song.
            let queue = state.queue
            Task { await container.toastService.perform { try await service.play(tracks: queue, startIndex: row) } }
        }
    }

    private func perform(_ item: WinampPlaylistMenuItem) {
        let count = player.queue.count
        switch item {
        case .addURL:
            // The server's folders, as a network location.
            host?.showFolderBrowser()
        case .addFolder:
            host?.localFiles?.add(folders: true)
        case .addFile:
            host?.localFiles?.add(folders: false)
        case .removeAll:
            remove(Set(0..<count))
        case .crop:
            remove(Set(0..<count).subtracting(selection.rows))
        case .removeSelected:
            removeSelected()
        case .removeMisc:
            remove(Set(WinampQueueReorder.duplicateIndices(player.queue.map(\.id), currentIndex: currentRow)))
        case .invertSelection:
            selection.invert(count: count)
        case .selectNone:
            selection.selectNone()
        case .selectAll:
            selection.selectAll(count: count)
        case .sort:
            popUp(sortMenu(), from: .misc)
        case .fileInfo:
            showInfo()
        case .options:
            popUp(optionsMenu(), from: .misc)
        case .newList:
            newList()
        case .saveList:
            let menu = NSMenu()
            addFileItems(to: menu, savingOnly: true)
            popUp(menu, from: .list)
        case .loadList:
            host?.playlistFiles?.open(replacing: true)
        }
        refresh()
    }

    private func popUp(_ menu: NSMenu, from kind: WinampPlaylistMenuKind) {
        let button = WinampPlaylistLayout.menuButton(kind, in: size.pixelSize)
        menu.popUp(positioning: nil, at: view.viewPoint(CGPoint(x: button.minX, y: button.minY)), in: view)
    }

    private func addFileItems(to menu: NSMenu, savingOnly: Bool = false) {
        let files = host?.playlistFiles
        let hasSongs = player.queue.contains { !$0.isLocalFile }
        menu.autoenablesItems = false
        menu.addItem(winampMenuItem(String(localized: "Save Playlist File…"), isEnabled: hasSongs) { files?.save() })
        menu.addItem(winampMenuItem(String(localized: "Save as Server Playlist…"),
                                    isEnabled: hasSongs && container.serverState.isOnline) { files?.saveToServer() })
        guard !savingOnly else { return }
        menu.addItem(winampMenuItem(String(localized: "Open Playlist File…")) { files?.open(replacing: true) })
        menu.addItem(winampMenuItem(String(localized: "Add Playlist File…")) { files?.open(replacing: false) })
    }

    private func sortMenu() -> NSMenu {
        let menu = NSMenu()
        for (key, title) in [(WinampQueueReorder.SortKey.title, String(localized: "Sort by Title")),
                             (.artist, String(localized: "Sort by Artist")),
                             (.album, String(localized: "Sort by Album")),
                             (.reverse, String(localized: "Reverse List")),
                             (.shuffle, String(localized: "Randomize List"))] {
            menu.addItem(winampMenuItem(title) { [weak self] in self?.sort(by: key) })
        }
        return menu
    }

    private func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(favoriteSelectionItem())
        menu.addItem(.separator())
        menu.addItem(winampMenuItem(String(localized: "Windowshade"), isOn: isShaded) { [weak self] in self?.toggleShade() })
        menu.addItem(winampZoomMenuItem(host: host))
        menu.addItem(winampMenuItem(String(localized: "Always on Top"), isOn: preferences.isAlwaysOnTop) { [weak self] in
            self?.host?.toggleAlwaysOnTop()
        })
        return menu
    }

    private func showInfo() {
        let queue = player.queue
        guard let row = selection.focus.flatMap({ selection.contains($0) ? $0 : nil }) ?? selection.rows.min(),
              queue.indices.contains(row) else { return }
        let song = queue[row]
        let alert = NSAlert()
        alert.messageText = song.title
        var lines: [String] = []
        if let artist = song.artist, !artist.isEmpty { lines.append(String(localized: "Artist: \(artist)")) }
        if let album = song.albumName, !album.isEmpty { lines.append(String(localized: "Album: \(album)")) }
        if song.duration > 0 { lines.append(String(localized: "Length: \(WinampPlaylistText.duration(song.duration))")) }
        if let format = song.audioFormat, !format.isEmpty { lines.append(String(localized: "Format: \(format)")) }
        alert.informativeText = lines.joined(separator: "\n")
        alert.runModal()
    }

    // MARK: Queue edits

    private func removeSelected() {
        remove(selection.rows)
    }

    /// Removes rows from the end so the earlier ones keep their places. A song that's playing
    /// stays; paused or stopped, the current song goes too, last, and the next one takes its place.
    private func remove(_ rows: Set<Int>) {
        guard editTask == nil, reorderTask == nil else { return }
        let current = currentRow
        let removesCurrent = current.map(rows.contains) == true && !player.wantsPlayback
        let targets = rows.filter { $0 != current }.sorted(by: >)
        guard !targets.isEmpty || removesCurrent else { return }
        let ids = player.queue
        let service = container.playerService
        editTask = Task { [weak self] in
            for row in targets {
                guard let self, !Task.isCancelled else { break }
                let state = self.player
                guard ids.indices.contains(row), state.queue.indices.contains(row), state.queue[row].id == ids[row].id,
                      let request = QueueTrackSelection(playerState: state, destinationIndex: row,
                                                        destinationTrackID: state.queue[row].id),
                      await service.removeQueueTrack(request) != nil else { break }
            }
            if removesCurrent { _ = await service.removeCurrentTrackIfNotPlaying() }
            guard let self else { return }
            self.selection.selectNone()
            self.editTask = nil
            self.refresh()
        }
    }

    /// LIST > NEW: Winamp's empty list. Playback stops and the queue is cleared.
    private func newList() {
        guard editTask == nil else { return }
        let service = container.playerService
        editTask = Task { [weak self] in
            await service.stop()
            self?.selection = WinampPlaylistSelection()
            self?.firstRow = 0
            self?.editTask = nil
            self?.refresh()
        }
    }

    private func sort(by key: WinampQueueReorder.SortKey) {
        var generator = SystemRandomNumberGenerator()
        let order = WinampQueueReorder.sortedOrder(player.queue, by: key, using: &generator)
        guard editTask == nil, reorderTask == nil,
              let moves = WinampQueueReorder.moves(toward: order, currentIndex: currentRow), !moves.isEmpty else { return }
        editTask = Task { [weak self] in
            _ = await self?.apply(moves)
            self?.selection = WinampPlaylistSelection()
            self?.editTask = nil
            self?.refresh()
        }
    }

    /// Option-arrow: the selection moves one row.
    private func shiftSelection(by delta: Int) {
        if case .some = interaction { return }
        guard !selection.rows.isEmpty else { return }
        reorderApplied = 0
        requestReorder(to: delta)
    }

    /// Moves the selection towards `target` rows from where the drag started, one row at a time.
    private func requestReorder(to target: Int) {
        reorderTarget = target
        guard reorderTask == nil, editTask == nil else { return }
        reorderTask = Task { [weak self] in
            await self?.runReorder()
            self?.reorderTask = nil
        }
    }

    private func runReorder() async {
        while reorderApplied != reorderTarget, !Task.isCancelled {
            let step = reorderTarget > reorderApplied ? 1 : -1
            let state = player
            let shifted = WinampQueueReorder.shifted(count: state.queue.count, selected: selection.rows, by: step)
            guard shifted.order != Array(shifted.order.indices),
                  let moves = WinampQueueReorder.moves(toward: shifted.order, currentIndex: currentRow),
                  await apply(moves) else {
                reorderTarget = reorderApplied
                break
            }
            selection.set(shifted.selection, focus: selection.focus.map { min(max($0 + step, 0), max(state.queue.count - 1, 0)) })
            reorderApplied += step
            revealFocus()
        }
    }

    /// Applies moves one at a time, each checked against the queue as it is now. Stops at the
    /// first the player refuses, such as after the queue changed underneath.
    private func apply(_ moves: [WinampQueueReorder.Move]) async -> Bool {
        let service = container.playerService
        for move in moves {
            let state = player
            guard state.queue.indices.contains(move.from),
                  let request = QueueTrackSelection(playerState: state, destinationIndex: move.from,
                                                    destinationTrackID: state.queue[move.from].id) else { return false }
            let revision = state.queueRevision
            await service.moveQueueTrack(request, toIndex: move.toOffset)
            guard player.queueRevision != revision else { return false }
        }
        return true
    }
}

import AppKit
import OSLog
import SwiftUI

/// What every Winamp window asks of Winamp mode: shared settings, docking and the other windows.
protocol WinampWindowHost: AnyObject {
    var preferences: WinampPreferences { get }
    /// The zoom level, 1 to 4: points per skin pixel.
    var scale: CGFloat { get }
    var isUsingDefaultSkin: Bool { get }
    var playlistFiles: WinampPlaylistFiles? { get }
    /// ADD > FILE and ADD > DIR: local audio files and folders.
    var localFiles: WinampLocalFiles? { get }

    /// A drag of the window's title bar: the main window brings its docked windows; another
    /// window moves alone, which undocks it.
    func beginDrag(_ window: WinampPreferences.Window)
    func continueDrag()
    func endDrag()
    /// A window changing size about its top-left corner, as for windowshade or a playlist resize.
    /// Windows docked below or beside it move to stay docked.
    func resize(_ window: WinampPreferences.Window, to size: CGSize)

    func isVisible(_ window: WinampPreferences.Window) -> Bool
    func toggle(_ window: WinampPreferences.Window)
    func close(_ window: WinampPreferences.Window)
    /// The clutter bar's D: 1× to 2×, or any other zoom back to 1×.
    func toggleDoubleSize()
    /// Zooms every window to `level` (1 to 4) together, keeping the stack docked and on screen.
    func setZoom(_ level: Int)
    func toggleAlwaysOnTop()
    func chooseSkin()
    func useDefaultSkin()
    func showFolderBrowser()
    /// The playlist's small transport buttons and keys, handled as the main window's.
    func performTransport(_ button: WinampPlaylistMiniButton)
}

/// A Winamp mode window: the main window, the equaliser or the playlist.
protocol WinampManagedWindow: AnyObject {
    var kind: WinampPreferences.Window { get }
    var window: WinampWindow { get }
    /// The window's size in skin pixels now, windowshade included.
    var logicalSize: CGSize { get }
    func show(at topLeft: CGPoint)
    func tearDown()
    func setSkin(_ skin: WinampSkin)
    /// Redraws after something another window controls changed, such as the zoom.
    func refresh()
}

/// Winamp mode, a hidden classic-player face for the Mac app. Its main, equaliser and playlist
/// windows drive the same PlayerService, so the queue, gapless playback and crossfade are shared.
/// View > Winamp Mode (⌘⇧W) turns it on, and it stays on across launches.
final class WinampMode: WinampWindowHost {
    static let shared = WinampMode()

    let preferences = WinampPreferences()
    private lazy var skins = WinampSkinStore(preferences: preferences)
    private var skin: WinampSkin?
    private var container: AppContainer?
    private var mainWindow: WinampMainWindowController?
    private var equalizerWindow: WinampEqualizerWindowController?
    private var playlistWindow: WinampPlaylistWindowController?
    private var folderBrowser: WinampFolderBrowserWindow?
    private(set) var playlistFiles: WinampPlaylistFiles?
    private(set) var localFiles: WinampLocalFiles?
    private var drag: Drag?
    private var autoEqualizerTrackID: String?
    private var isObservingTracks = false

    private struct Drag {
        let window: WinampPreferences.Window
        let mouse: NSPoint
        let frames: [WinampPreferences.Window: CGRect]
        let followers: Set<WinampPreferences.Window>
    }

    private init() {}

    /// Called once the app's services are ready; reopens the windows that were open at quit.
    func attach(_ container: AppContainer) {
        guard self.container !== container else { return }
        hide()
        mainWindow = nil
        equalizerWindow = nil
        playlistWindow = nil
        folderBrowser = nil
        self.container = container
        playlistFiles = WinampPlaylistFiles(container: container)
        localFiles = WinampLocalFiles(container: container)
        if preferences.isOpen { show() }
    }

    func setOpen(_ open: Bool) {
        preferences.isOpen = open
        if open { show() } else { hide() }
    }

    func chooseSkin() {
        Task {
            guard let url = await skins.chooseSkinFile() else { return }
            do {
                apply(try skins.adopt(url))
            } catch {
                Logger.ui.error("Winamp: couldn't load skin: \(String(describing: error), privacy: .public)")
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn't Load Skin")
                alert.informativeText = String(localized: "This file isn't a Winamp skin, or it's damaged.")
                alert.runModal()
            }
        }
    }

    func useDefaultSkin() {
        if let bundled = skins.useBundled() { apply(bundled) }
    }

    var isUsingDefaultSkin: Bool { preferences.skin == .bundled }

    var scale: CGFloat { CGFloat(preferences.zoom) }

    func showFolderBrowser() {
        guard let container else { return }
        let browser = folderBrowser ?? WinampFolderBrowserWindow(container: container)
        folderBrowser = browser
        browser.show()
    }

    func performTransport(_ button: WinampPlaylistMiniButton) {
        let control: WinampMainControl = switch button {
        case .previous: .previous
        case .play: .play
        case .pause: .pause
        case .stop: .stop
        case .next: .next
        case .eject: .eject
        }
        mainWindow?.performTransport(control)
    }

    // MARK: Windows

    private var managedWindows: [any WinampManagedWindow] {
        [mainWindow, equalizerWindow, playlistWindow].compactMap { $0 }
    }

    private func managed(_ kind: WinampPreferences.Window) -> (any WinampManagedWindow)? {
        switch kind {
        case .main: mainWindow
        case .equalizer: equalizerWindow
        case .playlist: playlistWindow
        }
    }

    private func show() {
        guard let container else { return }
        guard let skin = skin ?? skins.activeSkin() else { return }
        self.skin = skin
        if mainWindow == nil {
            mainWindow = WinampMainWindowController(container: container, skin: skin, host: self)
        }
        mainWindow?.show(at: placement(for: .main))
        for kind in [WinampPreferences.Window.equalizer, .playlist] where preferences.isVisible(kind) {
            open(kind)
        }
        mainWindow?.window.makeKeyAndOrderFront(nil)
        observeTracksForAuto()
    }

    private func hide() {
        for window in managedWindows { window.tearDown() }
        mainWindow = nil
        equalizerWindow = nil
        playlistWindow = nil
        folderBrowser?.close()
        isObservingTracks = false
    }

    private func open(_ kind: WinampPreferences.Window) {
        guard let container, let skin, mainWindow != nil else { return }
        switch kind {
        case .main:
            return
        case .equalizer:
            if equalizerWindow == nil {
                equalizerWindow = WinampEqualizerWindowController(model: EqualizerSettings.shared, skin: skin, host: self)
            }
        case .playlist:
            if playlistWindow == nil {
                playlistWindow = WinampPlaylistWindowController(container: container, skin: skin, host: self)
            }
        }
        managed(kind)?.show(at: placement(for: kind))
        applyLevel()
    }

    func isVisible(_ window: WinampPreferences.Window) -> Bool {
        managed(window)?.window.isVisible == true
    }

    func toggle(_ window: WinampPreferences.Window) {
        guard window != .main else { return }
        if isVisible(window) { close(window) } else {
            preferences.setVisible(true, window)
            open(window)
        }
        mainWindow?.refresh()
    }

    func close(_ window: WinampPreferences.Window) {
        guard window != .main else {
            setOpen(false)
            return
        }
        preferences.setVisible(false, window)
        managed(window)?.tearDown()
        switch window {
        case .main: break
        case .equalizer: equalizerWindow = nil
        case .playlist: playlistWindow = nil
        }
        mainWindow?.refresh()
    }

    /// The saved spot, or docked under the main window (and the equaliser) when it's new or no
    /// longer on any screen.
    private func placement(for kind: WinampPreferences.Window) -> CGPoint {
        let size = sizeOnScreen(kind)
        if let saved = preferences.topLeft(of: kind) {
            let titleBar = CGRect(x: saved.x, y: saved.y - 14 * scale, width: size.width, height: 14 * scale)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(titleBar) }) { return saved }
        }
        switch kind {
        case .main:
            let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            return CGPoint(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY + size.height / 2).rounded())
        case .equalizer, .playlist:
            let above = [WinampPreferences.Window.main, .equalizer, .playlist]
                .filter { $0 != kind && isVisible($0) }
                .compactMap { managed($0)?.window.frame }
                .min { $0.minY < $1.minY }
            guard let above else { return placement(for: .main) }
            return CGPoint(x: above.minX, y: above.minY)
        }
    }

    private func sizeOnScreen(_ kind: WinampPreferences.Window) -> CGSize {
        let fallback: CGSize = switch kind {
        case .main: WinampMainLayout.size
        case .equalizer: WinampEqualizerLayout.size
        case .playlist: preferences.playlistSize.pixelSize
        }
        let logical = managed(kind)?.logicalSize ?? fallback
        return CGSize(width: logical.width * scale, height: logical.height * scale)
    }

    private func apply(_ skin: WinampSkin) {
        self.skin = skin
        for window in managedWindows { window.setSkin(skin) }
    }

    private func applyLevel() {
        let level: NSWindow.Level = preferences.isAlwaysOnTop ? .floating : .normal
        for window in managedWindows { window.window.level = level }
    }

    func toggleAlwaysOnTop() {
        preferences.isAlwaysOnTop.toggle()
        applyLevel()
        for window in managedWindows { window.refresh() }
    }

    func toggleDoubleSize() {
        setZoom(WinampZoom.toggledDoubleSize(from: preferences.zoom))
    }

    /// Zoom for every window, scaled about the main window's top-left corner so docked windows
    /// stay docked, then moved back onto the screen if the bigger stack ran off its edge.
    func setZoom(_ level: Int) {
        let old = preferences.zoom
        let new = WinampZoom.clamped(level)
        guard new != old else { return }
        preferences.zoom = new
        let visible = managedWindows.filter { $0.window.isVisible }
        guard let anchor = visible.firstIndex(where: { $0.kind == .main }) else { return }
        let frames = WinampDocking.zoom(visible.map(\.window.frame), anchor: anchor, from: old, to: new,
                                        screens: NSScreen.screens.map(\.visibleFrame))
        for (managed, frame) in zip(visible, frames) {
            managed.window.setFrame(frame, display: true)
            managed.window.invalidateShadow()
            managed.refresh()
            preferences.setTopLeft(CGPoint(x: frame.minX, y: frame.maxY), of: managed.kind)
        }
    }

    // MARK: Docking

    func beginDrag(_ window: WinampPreferences.Window) {
        let visible = managedWindows.filter { $0.window.isVisible }
        var frames: [WinampPreferences.Window: CGRect] = [:]
        for managed in visible { frames[managed.kind] = managed.window.frame }
        var followers: Set<WinampPreferences.Window> = []
        if window == .main, let index = visible.firstIndex(where: { $0.kind == .main }) {
            let group = WinampDocking.dockedGroup(root: index, frames: visible.map(\.window.frame))
            followers = Set(group.map { visible[$0].kind })
        }
        drag = Drag(window: window, mouse: NSEvent.mouseLocation, frames: frames, followers: followers)
    }

    func continueDrag() {
        guard let drag, let start = drag.frames[drag.window] else { return }
        let mouse = NSEvent.mouseLocation
        let proposed = start.offsetBy(dx: mouse.x - drag.mouse.x, dy: mouse.y - drag.mouse.y)
        let others = drag.frames.filter { $0.key != drag.window && !drag.followers.contains($0.key) }.map(\.value)
        let snapped = WinampDocking.snap(proposed, to: others, screens: NSScreen.screens.map(\.visibleFrame))
        let dx = snapped.minX - start.minX
        let dy = snapped.minY - start.minY
        for kind in [drag.window] + Array(drag.followers) {
            guard let frame = drag.frames[kind], let window = managed(kind)?.window else { continue }
            window.setFrameOrigin(NSPoint(x: frame.minX + dx, y: frame.minY + dy))
        }
    }

    func endDrag() {
        guard let drag else { return }
        self.drag = nil
        for kind in [drag.window] + Array(drag.followers) {
            guard let frame = managed(kind)?.window.frame else { continue }
            preferences.setTopLeft(CGPoint(x: frame.minX, y: frame.maxY), of: kind)
        }
    }

    func resize(_ window: WinampPreferences.Window, to size: CGSize) {
        guard let target = managed(window) else { return }
        let old = target.window.frame
        let newFrame = CGRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        let visible = managedWindows.filter { $0.window.isVisible || $0.kind == window }
        guard let index = visible.firstIndex(where: { $0.kind == window }) else { return }
        let frames = WinampDocking.resize(visible.map(\.window.frame), index: index, to: newFrame)
        for (managed, frame) in zip(visible, frames) where managed.window.frame != frame {
            managed.window.setFrame(frame, display: true)
            managed.window.invalidateShadow()
            preferences.setTopLeft(CGPoint(x: frame.minX, y: frame.maxY), of: managed.kind)
        }
    }

    // MARK: Equaliser AUTO

    /// While AUTO is on, each new song applies the built-in preset for its genre.
    private func observeTracksForAuto() {
        guard let container, !isObservingTracks else { return }
        isObservingTracks = true
        trackDidChange(container.playerState.currentTrack)
        watchTrack()
    }

    private func watchTrack() {
        guard isObservingTracks, let container else { return }
        withObservationTracking {
            _ = container.playerState.currentTrack?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let container = self.container else { return }
                self.trackDidChange(container.playerState.currentTrack)
                self.watchTrack()
            }
        }
    }

    private func trackDidChange(_ track: DisplayableSong?) {
        guard let track, track.id != autoEqualizerTrackID else { return }
        autoEqualizerTrackID = track.id
        guard preferences.isEqualizerAuto, let preset = WinampAutoEqualizer.preset(forGenre: track.genre) else { return }
        EqualizerSettings.shared.apply(preset)
    }

    /// AUTO switched on: apply the playing song's preset straight away.
    func equalizerAutoDidChange() {
        autoEqualizerTrackID = nil
        trackDidChange(container?.playerState.currentTrack)
    }
}

extension EqualizerSettings: WinampEqualizerModel {}

/// The Zoom submenu in the Winamp windows' menus: 1× to 4×, the current level ticked. The View
/// menu has the same items with ⌘⌥1 to ⌘⌥4.
func winampZoomMenuItem(host: WinampWindowHost?) -> NSMenuItem {
    let title = String(localized: "Zoom")
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    let current = host?.preferences.zoom ?? 1
    for level in WinampZoom.levels {
        let option = winampMenuItem(WinampZoom.title(level), isOn: level == current) { [weak host] in host?.setZoom(level) }
        option.keyEquivalent = String(level)
        option.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(option)
    }
    item.submenu = menu
    return item
}

/// View > Winamp Mode, plus the skin and window items while it's on.
struct WinampCommands: Commands {
    @AppStorage(WinampPreferences.Key.isOpen) private var isOpen = false
    @AppStorage(WinampPreferences.Key.zoom) private var zoom = 1

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle("Winamp Mode", isOn: Binding(get: { isOpen }, set: { WinampMode.shared.setOpen($0) }))
                .keyboardShortcut("w", modifiers: [.command, .shift])
            if isOpen {
                Button("Winamp Equalizer") { WinampMode.shared.toggle(.equalizer) }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                Button("Winamp Playlist") { WinampMode.shared.toggle(.playlist) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Menu("Winamp Zoom") {
                    ForEach(Array(WinampZoom.levels), id: \.self) { level in
                        Toggle(WinampZoom.title(level), isOn: Binding(
                            get: { WinampZoom.clamped(zoom) == level },
                            set: { if $0 { WinampMode.shared.setZoom(level) } }
                        ))
                        .keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option])
                    }
                }
                Button("Open Playlist File…") { WinampMode.shared.playlistFiles?.open(replacing: true) }
                Button("Save Playlist File…") { WinampMode.shared.playlistFiles?.save() }
                Button("Load Skin…") { WinampMode.shared.chooseSkin() }
                Button("Default Skin") { WinampMode.shared.useDefaultSkin() }
            }
        }
    }
}

extension View {
    /// Hands the app's services to Winamp mode once they're ready.
    func winampMode(_ container: AppContainer?) -> some View {
        task(id: container.map(ObjectIdentifier.init)) {
            if let container { WinampMode.shared.attach(container) }
        }
    }
}

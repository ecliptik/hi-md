import AppKit

/// Miniamp's MilkDrop window: projectM drawing the music with MilkDrop presets. It reads the
/// same audio tap as Miniamp's own visualizer, only while it's open, and draws once per display
/// refresh while it can be seen.
@MainActor
final class MilkDropWindowController: NSWindowController, NSWindowDelegate {
    private enum Key {
        static let presetDuration = "milkdrop.presetDuration"
    }

    private static var instance: MilkDropWindowController?
    static var shared: MilkDropWindowController {
        if let instance { return instance }
        let controller = MilkDropWindowController()
        instance = controller
        return controller
    }

    /// Closes the window if it was ever opened, as when Miniamp closes.
    static func closeIfOpen() {
        instance?.close()
    }

    static var isOpen: Bool { instance?.window?.isVisible == true }

    /// MilkDrop stacks with Miniamp's windows, at their level, so they can't cover it; whichever
    /// was clicked last is in front. Full screen keeps the normal level of its own space.
    static func setLevel(_ level: NSWindow.Level) {
        guard let window = instance?.window, !window.styleMask.contains(.fullScreen), window.level != level else { return }
        window.level = level
    }

    static var durations: [Double] { MilkDropDriver.durations }

    private let driver = MilkDropDriver(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    private var canvas: MilkDropCanvas { driver.canvas }
    private var library: MilkDropPresetLibrary { driver.library }
    var isLocked: Bool { driver.isLocked }
    private var presetDuration: Double { driver.presetDuration }
    private var presetName: String? { driver.presetName }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(localized: "MilkDrop")
        window.minSize = NSSize(width: 275, height: 160)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        super.init(window: window)
        window.contentView = canvas
        window.delegate = self
        window.setFrameAutosaveName("MilkDrop")
        if !window.setFrameUsingName("MilkDrop") { window.center() }
        canvas.controller = self
        driver.onPresetChange = { [weak self] in self?.updateTitle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Showing

    func toggle() {
        if window?.isVisible == true { close() } else { show() }
    }

    func show() {
        window?.level = WinampMode.shared.windowLevel
        showWindow(nil)
        window?.makeFirstResponder(canvas)
        driver.start()
        updateTitle()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.level = .normal
        WinampMode.shared.stepAside(forFullScreen: true)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.level = WinampMode.shared.windowLevel
        WinampMode.shared.stepAside(forFullScreen: false)
    }

    func windowWillClose(_ notification: Notification) {
        // Closed from full screen, Miniamp comes back.
        WinampMode.shared.stepAside(forFullScreen: false)
        driver.stop()
    }

    // MARK: - Presets

    func nextPreset(smooth: Bool = true) { driver.nextPreset(smooth: smooth) }
    func previousPreset() { driver.previousPreset() }
    func toggleLock() { driver.toggleLock() }
    func setPresetDuration(_ seconds: Double) { driver.presetDuration = seconds }
    func chooseFolder() { driver.chooseFolder() }
    func useBuiltInPresetsOnly() { driver.useBuiltInPresetsOnly() }
    func showFolderInFinder() { driver.showFolderInFinder() }

    private func updateTitle() {
        guard let name = presetName else {
            window?.title = String(localized: "MilkDrop")
            return
        }
        window?.title = isLocked ? String(localized: "MilkDrop — \(name) (Locked)") : String(localized: "MilkDrop — \(name)")
    }

    // MARK: - Keys and menu

    /// MilkDrop's keys: → or N next, ← or Delete previous, R random cut, L lock, F full screen.
    /// Space stays Play and Pause, as everywhere in Hi-MD.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        // The arrows, Delete and Escape by key; letters by character, for any layout.
        switch event.keyCode {
        case 124: nextPreset()
        case 123, 51: previousPreset()
        case 53:
            guard window?.styleMask.contains(.fullScreen) == true else { return false }
            window?.toggleFullScreen(nil)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n": nextPreset()
            case "p": previousPreset()
            case "r": nextPreset(smooth: false)
            case "l": toggleLock()
            case "f": window?.toggleFullScreen(nil)
            default: return false
            }
        }
        return true
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let presetName {
            let current = NSMenuItem(title: presetName, action: nil, keyEquivalent: "")
            current.isEnabled = false
            menu.addItem(current)
            menu.addItem(.separator())
        }
        menu.addItem(item(String(localized: "Next Preset"), key: "n") { $0.nextPreset() })
        menu.addItem(item(String(localized: "Previous Preset"), key: "\u{7F}") { $0.previousPreset() })
        menu.addItem(item(String(localized: "Random Preset"), key: "r") { $0.nextPreset(smooth: false) })
        menu.addItem(item(String(localized: "Lock Preset"), key: "l", isOn: isLocked) { $0.toggleLock() })
        let every = NSMenuItem(title: String(localized: "Change Preset Every"), action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for seconds in Self.durations {
            durations.addItem(item(String(localized: "\(Int(seconds)) Seconds"), isOn: presetDuration == seconds) {
                $0.setPresetDuration(seconds)
            })
        }
        every.submenu = durations
        menu.addItem(every)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Choose Preset Folder…")) { $0.chooseFolder() })
        if let folder = library.folderName {
            menu.addItem(item(String(localized: "Show “\(folder)” in Finder")) { $0.showFolderInFinder() })
            menu.addItem(item(String(localized: "Use Built-In Presets Only")) { $0.useBuiltInPresetsOnly() })
        }
        menu.addItem(.separator())
        let fullScreen = window?.styleMask.contains(.fullScreen) == true
        menu.addItem(item(fullScreen ? String(localized: "Exit Full Screen") : String(localized: "Enter Full Screen"), key: "f") {
            $0.window?.toggleFullScreen(nil)
        })
        return menu
    }

    private func item(_ title: String, key: String = "", isOn: Bool? = nil,
                      _ action: @escaping (MilkDropWindowController) -> Void) -> NSMenuItem {
        let target = MilkDropMenuAction { [weak self] in
            guard let self else { return }
            action(self)
        }
        let item = NSMenuItem(title: title, action: #selector(MilkDropMenuAction.run(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = []
        item.target = target
        item.representedObject = target
        if let isOn { item.state = isOn ? .on : .off }
        return item
    }
}

/// Runs a closure for a menu item, which keeps it alive as its represented object.
private final class MilkDropMenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) {
        handler()
    }
}

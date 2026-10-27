import AppKit
import SwiftUI

/// The MiniPlayer's window settings, under Window in the menu bar and in its … menu.
@MainActor
enum MiniPlayerSettings {
    /// On by default: the MiniPlayer stays above other windows, as Plexamp's and the Music app's do.
    static let floatsOnTopKey = "minidisc.mac.miniPlayerFloatsOnTop"
    /// Off by default: opening the MiniPlayer puts the main window away, for using the MiniPlayer
    /// instead of it. Closing the MiniPlayer brings it back.
    static let hidesMainWindowKey = "minidisc.mac.miniPlayerHidesMainWindow"
    /// Off by default: the MiniPlayer shows as a bar of controls rather than the artwork. Kept
    /// across launches.
    static let showsBarKey = "minidisc.mac.miniPlayerBar"

    /// The main windows the MiniPlayer put away, by window number, so closing it brings back
    /// exactly those and nothing else.
    private static var hiddenMainWindows: Set<Int> = []

    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter {
            $0.identifier?.rawValue.hasPrefix(MacMenuBarPlayer.mainWindowID) == true
                && $0.identifier?.rawValue.hasPrefix(MacMiniPlayer.windowID) != true
        }
    }

    static func hideMainWindows() {
        let visible = mainWindows.filter(\.isVisible)
        guard !visible.isEmpty else { return }
        visible.forEach { $0.orderOut(nil) }
        hiddenMainWindows.formUnion(visible.map(\.windowNumber))
    }

    /// Brings back the main windows the MiniPlayer hid, or one if none is showing, so closing the
    /// MiniPlayer never leaves the app without a window. A main window that's showing is left
    /// exactly as it is: its frame (zoomed, tiled or resized) is never touched.
    static func miniPlayerDidClose(openMainWindow: () -> Void) {
        let hidden = hiddenMainWindows
        hiddenMainWindows = []
        reveal(hidden: hidden, openMainWindow: openMainWindow)
    }

    /// Show Hi-MD: the main window comes forward as it is, or comes back if it was put away or
    /// minimised; a new one opens only when there's none.
    static func showMainWindow(openMainWindow: () -> Void) {
        NSApp.activate()
        if let visible = mainWindows.first(where: \.isVisible) {
            visible.makeKeyAndOrderFront(nil)
            return
        }
        let hidden = hiddenMainWindows
        hiddenMainWindows = []
        reveal(hidden: hidden, openMainWindow: openMainWindow)
    }

    private static func reveal(hidden: Set<Int>, openMainWindow: () -> Void) {
        let windows = mainWindows
        let states = windows.map {
            MiniPlayerWindowIdentity.MainWindow(number: $0.windowNumber, isVisible: $0.isVisible,
                                                isMiniaturized: $0.isMiniaturized)
        }
        func window(_ number: Int) -> NSWindow? { windows.first { $0.windowNumber == number } }
        switch MiniPlayerWindowIdentity.reveal(mainWindows: states, hiddenByMiniPlayer: hidden) {
        case .none:
            return
        case .orderFront(let numbers):
            // Ordered back in at the frame they had: no resize, no zoom.
            for (offset, number) in numbers.enumerated() {
                if offset == 0 { window(number)?.makeKeyAndOrderFront(nil) } else { window(number)?.orderFront(nil) }
            }
        case .deminiaturize(let number):
            window(number)?.deminiaturize(nil)
        case .openNew:
            openMainWindow()
        }
    }
}

/// Window > MiniPlayer as Bar (⌥⌘B), Float MiniPlayer on Top and Hide Main Window with
/// MiniPlayer.
struct MiniPlayerCommands: Commands {
    @AppStorage(MiniPlayerSettings.floatsOnTopKey) private var floatsOnTop = true
    @AppStorage(MiniPlayerSettings.hidesMainWindowKey) private var hidesMainWindow = false
    @AppStorage(MiniPlayerSettings.showsBarKey) private var showsBar = false
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            // The open MiniPlayer follows the setting and resizes itself; turning it on with the
            // MiniPlayer closed opens it as the bar.
            Toggle("MiniPlayer as Bar", isOn: Binding(get: { showsBar }, set: { isOn in
                showsBar = isOn
                if isOn { openWindow(id: MacMiniPlayer.windowID) }
            }))
            .keyboardShortcut("b", modifiers: [.command, .option])
            Toggle("Float MiniPlayer on Top", isOn: $floatsOnTop)
            Toggle("Hide Main Window with MiniPlayer", isOn: $hidesMainWindow)
        }
    }
}

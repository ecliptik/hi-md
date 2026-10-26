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

    /// Set when the MiniPlayer put the main window away, so closing it knows to bring it back.
    private static var hidMainWindow = false

    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix(MacMenuBarPlayer.mainWindowID) == true }
    }

    static func hideMainWindows() {
        let visible = mainWindows.filter(\.isVisible)
        guard !visible.isEmpty else { return }
        visible.forEach { $0.orderOut(nil) }
        hidMainWindow = true
    }

    /// Brings the main window back if the MiniPlayer hid it, or if none is open, so closing the
    /// MiniPlayer never leaves the app without a window.
    static func miniPlayerDidClose(showMainWindow: () -> Void) {
        let hid = hidMainWindow
        hidMainWindow = false
        if hid, let window = mainWindows.first {
            window.makeKeyAndOrderFront(nil)
        } else if !mainWindows.contains(where: \.isVisible) {
            showMainWindow()
        }
    }
}

/// Window > Float MiniPlayer on Top and Hide Main Window with MiniPlayer.
struct MiniPlayerCommands: Commands {
    @AppStorage(MiniPlayerSettings.floatsOnTopKey) private var floatsOnTop = true
    @AppStorage(MiniPlayerSettings.hidesMainWindowKey) private var hidesMainWindow = false

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Toggle("Float MiniPlayer on Top", isOn: $floatsOnTop)
            Toggle("Hide Main Window with MiniPlayer", isOn: $hidesMainWindow)
        }
    }
}

import AppKit

/// Plays and pauses with the space bar, as the Music app does, without taking spaces from text
/// fields. A menu shortcut would see every space first, so this watches key presses in the app
/// and leaves the decision to PlaybackKeyRouting.
@MainActor
final class MacSpaceKeyMonitor {
    static let shared = MacSpaceKeyMonitor()

    private var monitor: Any?
    private weak var playback: MacPlayback?

    /// Installs the monitor once; later calls only point it at the current playback.
    func install(playback: MacPlayback) {
        self.playback = playback
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // AppKit calls local monitors on the main thread.
            let handled = MainActor.assumeIsolated { MacSpaceKeyMonitor.shared.handle(event) }
            return handled ? nil : event
        }
    }

    /// Returns true when the event was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard let playback else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = PlaybackKeyRouting.KeyPress(isSpace: event.keyCode == Self.spaceKeyCode,
                                              hasModifiers: !modifiers.isEmpty, isRepeat: event.isARepeat)
        let window = NSApp.keyWindow
        let context = PlaybackKeyRouting.Context(
            isEditingText: Self.isEditingText(window?.firstResponder),
            isMainWindowFocused: window.map(Self.isMainContentWindow) ?? false,
            canTogglePlayback: playback.commands.canTogglePlayback
        )
        switch PlaybackKeyRouting.decision(for: key, in: context) {
        case .togglePlayback:
            playback.togglePlayPause()
            return true
        case .ignore:
            return true
        case .passThrough:
            return false
        }
    }

    private static let spaceKeyCode: UInt16 = 49

    /// Text fields edit through a shared text view, and other editors take input through
    /// NSTextInputClient, so either one having focus means a space is typing.
    private static func isEditingText(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSText || responder is NSTextInputClient { return true }
        if let field = responder as? NSTextField, field.isEditable { return true }
        return false
    }

    /// The main window, as opposed to a sheet on it, an alert, Settings or the menu bar panel.
    private static func isMainContentWindow(_ window: NSWindow) -> Bool {
        window.isMainWindow && window.attachedSheet == nil && !window.isSheet && !(window is NSPanel)
            && window.styleMask.contains(.titled) && window.identifier?.rawValue.contains("Settings") != true
            && window.canBecomeMain
    }
}

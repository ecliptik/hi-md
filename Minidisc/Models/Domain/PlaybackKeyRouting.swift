import Foundation

/// Decides what the Mac app does with a press of the space bar, its Play/Pause key.
///
/// A menu shortcut would take every space before the focused view saw it, so typing in the search
/// field or a playlist name would pause the music. The app watches key presses instead and only
/// claims a plain space when nothing that takes text has focus.
nonisolated enum PlaybackKeyRouting {
    enum Decision: Equatable, Sendable {
        case togglePlayback
        /// A held space bar repeats; the first press already toggled playback.
        case ignore
        /// The key belongs to the focused view or window.
        case passThrough
    }

    struct KeyPress: Equatable, Sendable {
        var isSpace: Bool
        /// Command, Option, Control or Shift was held. Caps Lock and Fn don't count.
        var hasModifiers = false
        var isRepeat = false
    }

    struct Context: Equatable, Sendable {
        /// A text field, text view or input method has focus.
        var isEditingText: Bool
        /// The main window has focus, rather than a sheet, an alert, Settings or the menu bar panel,
        /// where the space bar presses the focused button.
        var isMainWindowFocused: Bool
        var canTogglePlayback: Bool
    }

    static func decision(for key: KeyPress, in context: Context) -> Decision {
        guard key.isSpace, !key.hasModifiers,
              !context.isEditingText, context.isMainWindowFocused, context.canTogglePlayback else {
            return .passThrough
        }
        return key.isRepeat ? .ignore : .togglePlayback
    }
}

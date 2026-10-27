import Foundation

/// When the Mac player surfaces show their controls, as the Music app's MiniPlayer and full-screen
/// player do: the controls (and the window's traffic lights) come in with the pointer or a click
/// and go again after `idleDelay` without one. They stay while something needs them: VoiceOver,
/// a control with keyboard focus, an open menu or popover, or a scrub in progress. Letting go of
/// the last of those starts the idle wait again rather than hiding them at once.
///
/// Times are seconds on any steady clock; the views pass `ProcessInfo.systemUptime`.
nonisolated struct PlayerChromeVisibility: Equatable, Sendable {
    /// What keeps the controls on screen however long the pointer rests.
    enum Pin: Hashable, Sendable, CaseIterable {
        case voiceOver
        case keyboardFocus
        case menu
        case popover
        case scrubbing
    }

    /// How long the controls stay after the last activity.
    static let idleDelay: TimeInterval = 2.5

    private(set) var lastActivity: TimeInterval?
    private(set) var pins: Set<Pin> = []

    var isPinned: Bool { !pins.isEmpty }

    /// The pointer moved, or a click or key press happened.
    mutating func registerActivity(at now: TimeInterval) {
        lastActivity = now
    }

    /// The pointer left the surface: the controls go now, unless something keeps them.
    mutating func pointerExited() {
        lastActivity = nil
    }

    /// Turns a reason to stay on or off. Releasing the last one counts as activity, so a closing
    /// menu or a finished scrub leaves the controls for the usual idle wait.
    mutating func set(_ pin: Pin, _ isOn: Bool, at now: TimeInterval) {
        if isOn {
            pins.insert(pin)
        } else if pins.remove(pin) != nil, pins.isEmpty {
            lastActivity = now
        }
    }

    func isVisible(at now: TimeInterval) -> Bool {
        if isPinned { return true }
        guard let lastActivity else { return false }
        return now - lastActivity < Self.idleDelay
    }

    /// When the controls will hide on their own, or nil when they won't (pinned, or already
    /// hidden).
    func hideDeadline(after now: TimeInterval) -> TimeInterval? {
        guard !isPinned, let lastActivity else { return nil }
        let deadline = lastActivity + Self.idleDelay
        return deadline > now ? deadline : nil
    }
}

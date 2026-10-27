import AppKit
import SwiftUI

/// The click target that swaps the player's artwork for the spinning MiniDisc: only the circle in
/// the middle of the artwork, clear of the controls over it (`ArtworkDiscHitArea`). Everywhere
/// else on the artwork is the window's background, so the MiniPlayer is dragged from there as
/// before. Inside the circle a press that drags the window, moves the pointer, or is the second
/// click of a double-click leaves the artwork alone (`ArtworkDiscClick`).
///
/// Hidden from VoiceOver: the artwork itself carries the Show Spinning Disc / Show Artwork action.
struct MacArtworkDiscTarget: View {
    let area: ArtworkDiscHitArea
    let title: Text
    let action: () -> Void

    var body: some View {
        let rect = area.clearRect
        if rect.width > 1, rect.height > 1 {
            Button(action: click) {
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(ArtworkDiscHitShape(area: area, origin: rect.origin))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(title)
            .accessibilityHidden(true)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .frame(width: area.size.width, height: area.size.height, alignment: .topLeading)
            .onAppear { MacPressTracker.shared.install() }
        }
    }

    /// The button fires on release; it toggles only for a still, single click. It takes neither
    /// keyboard focus nor VoiceOver (the artwork has the action for that), so a pointer press is
    /// always behind it.
    private func click() {
        guard let press = MacPressTracker.shared.lastPress, let window = press.window else { return }
        let release = NSApp.currentEvent.flatMap { $0.type == .leftMouseUp ? $0.clickCount : nil } ?? 0
        let click = ArtworkDiscClick(screenLocation: press.screenLocation, windowFrame: press.windowFrame,
                                     clickCount: max(press.clickCount, release), isInArea: true)
        // The button only takes presses that began and ended inside the circle.
        if click.toggles(releasedAt: NSEvent.mouseLocation, windowFrame: window.frame, isInArea: true) {
            action()
        }
    }
}

/// The circle less the controls' surroundings, in the target's own coordinates.
private nonisolated struct ArtworkDiscHitShape: Shape {
    let area: ArtworkDiscHitArea
    let origin: CGPoint

    func path(in rect: CGRect) -> Path {
        let shift = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        var path = Path(ellipseIn: area.circle).applying(shift)
        for excluded in area.excluded {
            path = path.subtracting(Path(excluded.applying(shift)))
        }
        return path
    }
}

/// The last left-button press in the app: where on screen, which window and its frame then, and
/// its click count. A click that releases elsewhere, or after the window moved, was a drag.
@MainActor
final class MacPressTracker {
    struct Press {
        let screenLocation: CGPoint
        weak var window: NSWindow?
        let windowFrame: CGRect
        let clickCount: Int
    }

    static let shared = MacPressTracker()

    private(set) var lastPress: Press?
    private var monitor: Any?

    /// Watches presses without taking them: the event goes on as before.
    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            // AppKit calls local monitors on the main thread.
            MainActor.assumeIsolated {
                MacPressTracker.shared.lastPress = Press(
                    screenLocation: NSEvent.mouseLocation, window: event.window,
                    windowFrame: event.window?.frame ?? .zero, clickCount: event.clickCount)
            }
            return event
        }
    }
}

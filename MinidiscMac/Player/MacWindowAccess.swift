import AppKit
import SwiftUI

/// The window a view is in, for what SwiftUI doesn't offer: resizing it for the chevron and
/// showing the traffic lights only while the pointer is over it.
@MainActor
final class MacWindowHandle {
    weak var window: NSWindow?

    /// Hides or shows the close, minimise and zoom buttons. They stay in place, and VoiceOver
    /// still finds them.
    func setTrafficLightsVisible(_ visible: Bool, animated: Bool) {
        guard let window else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            for button in buttons { button.animator().alphaValue = visible ? 1 : 0 }
        }
    }

    /// Resizes the content to `size`, keeping the top edge where it is and the window on screen.
    func resizeContent(to size: CGSize, animated: Bool) {
        guard let window else { return }
        let old = window.frame
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        if let visible = window.screen?.visibleFrame {
            frame.size.height = min(frame.height, visible.height)
            frame.size.width = min(frame.width, visible.width)
            frame.origin.x = min(max(old.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = max(old.maxY - frame.height, visible.minY)
        } else {
            frame.origin = CGPoint(x: old.minX, y: old.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: animated)
    }
}

struct MacWindowReader: NSViewRepresentable {
    let handle: MacWindowHandle
    var onWindow: ((NSWindow) -> Void)?

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = { [handle, onWindow] window in
            handle.window = window
            if let window { onWindow?(window) }
        }
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

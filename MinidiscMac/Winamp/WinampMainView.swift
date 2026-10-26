import AppKit

/// The borderless window Winamp mode draws its own frame into.
final class WinampWindow: NSWindow {
    /// Called for ⌘W and the File menu's Close, which a borderless window can't handle itself.
    var closeHandler: (() -> Void)?

    init(contentSize: CGSize) {
        // Borderless with no title bar. Miniaturizable lets the skin's minimize button work.
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Only the title bar drags the window, as in Winamp; the view starts that drag itself.
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        // Winamp mode reopens and places the window itself.
        isRestorable = false
        collectionBehavior = [.fullScreenNone]
        title = "Winamp"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        closeHandler?()
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)) { return true }
        return super.validateMenuItem(menuItem)
    }
}

/// What the main window's view reports to its controller, in 275×116 window pixels.
protocol WinampMainViewDelegate: AnyObject {
    func mainView(_ view: WinampMainView, mouseDownAt point: CGPoint, event: NSEvent)
    func mainView(_ view: WinampMainView, mouseDraggedTo point: CGPoint)
    func mainView(_ view: WinampMainView, mouseUpAt point: CGPoint)
    func mainView(_ view: WinampMainView, keyDown event: NSEvent) -> Bool
    func contextMenu(for view: WinampMainView) -> NSMenu?
}

/// Shows the rendered main window. Each state change renders a fresh 275×116 bitmap that the
/// layer scales up with nearest-neighbour filtering, so sprites stay pixel-exact at 1× and 2× on
/// any display.
final class WinampMainView: NSView {
    weak var delegate: WinampMainViewDelegate?

    var skin: WinampSkin {
        didSet {
            sprites = WinampSpriteCache(skin: skin)
            shape = WinampWindowShape(skin: skin)
            needsDisplay = true
            window?.invalidateShadow()
        }
    }

    var state = WinampMainDisplayState() {
        didSet {
            if state != oldValue { needsDisplay = true }
        }
    }

    private var sprites: WinampSpriteCache
    private var shape: WinampWindowShape

    init(skin: WinampSkin) {
        self.skin = skin
        sprites = WinampSpriteCache(skin: skin)
        shape = WinampWindowShape(skin: skin)
        super.init(frame: NSRect(origin: .zero, size: WinampMainLayout.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Winamp Mode"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resize
        layer.contents = WinampMainRenderer.render(state, skin: skin, sprites: sprites)
    }

    /// The same picture for snapshots and `cacheDisplay`, which draw rather than read the layer.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = WinampMainRenderer.render(state, skin: skin, sprites: sprites) else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Winamp answers the first click even when it isn't the active window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks outside the skin's window shape fall through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        guard bounds.contains(local), shape.contains(winampPoint(local)) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        delegate?.mainView(self, mouseDownAt: winampPoint(event), event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.mainView(self, mouseDraggedTo: winampPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.mainView(self, mouseUpAt: winampPoint(event))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.contextMenu(for: self)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.mainView(self, keyDown: event) != true {
            super.keyDown(with: event)
        }
    }

    /// A point in the view, in window pixels from the top left.
    private func winampPoint(_ local: NSPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(x: local.x * WinampMainLayout.size.width / bounds.width,
                       y: (bounds.height - local.y) * WinampMainLayout.size.height / bounds.height)
    }

    private func winampPoint(_ event: NSEvent) -> CGPoint {
        winampPoint(convert(event.locationInWindow, from: nil))
    }
}

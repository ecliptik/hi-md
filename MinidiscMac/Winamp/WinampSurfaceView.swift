import AppKit

/// What a skinned window's view asks of its controller. Points are in skin pixels from the top
/// left of the window, whatever its size on screen.
protocol WinampSurfaceDelegate: AnyObject {
    func surfaceImage(_ view: WinampSurfaceView, pixelScale: CGFloat) -> CGImage?
    func surface(_ view: WinampSurfaceView, mouseDownAt point: CGPoint, event: NSEvent)
    func surface(_ view: WinampSurfaceView, mouseDraggedTo point: CGPoint, event: NSEvent)
    func surface(_ view: WinampSurfaceView, mouseUpAt point: CGPoint, event: NSEvent)
    func surface(_ view: WinampSurfaceView, scrollWheel event: NSEvent)
    func surface(_ view: WinampSurfaceView, keyDown event: NSEvent) -> Bool
    func surface(_ view: WinampSurfaceView, menuAt point: CGPoint) -> NSMenu?
}

/// Shows a skinned window that its controller renders on demand: the equaliser and the playlist.
/// Each change renders a fresh bitmap at the screen's pixel density, so sprites scale with
/// nearest-neighbour filtering and the playlist's text stays sharp.
final class WinampSurfaceView: NSView {
    weak var delegate: WinampSurfaceDelegate?

    /// The window's size in skin pixels; the view's bounds are this times the zoom.
    var logicalSize: CGSize {
        didSet { if logicalSize != oldValue { needsDisplay = true } }
    }

    init(logicalSize: CGSize, accessibilityLabel: String) {
        self.logicalSize = logicalSize
        super.init(frame: NSRect(origin: .zero, size: logicalSize))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func refresh() {
        needsDisplay = true
    }

    /// Bitmap pixels per skin pixel: the zoom times the display's density. The zoom is rounded to
    /// a whole number so every skin pixel covers the same number of bitmap pixels.
    private var pixelScale: CGFloat {
        let scale = logicalSize.width > 0 ? bounds.width / logicalSize.width : 1
        return max(scale.rounded(), 1) * (window?.backingScaleFactor ?? 2)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .linear
        layer.contentsGravity = .resize
        layer.contents = delegate?.surfaceImage(self, pixelScale: pixelScale)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    /// The same picture for `cacheDisplay`, which draws rather than reading the layer.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = delegate?.surfaceImage(self, pixelScale: pixelScale) else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        delegate?.surface(self, mouseDownAt: skinPoint(event), event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.surface(self, mouseDraggedTo: skinPoint(event), event: event)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.surface(self, mouseUpAt: skinPoint(event), event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        delegate?.surface(self, scrollWheel: event)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.surface(self, keyDown: event) != true {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.surface(self, menuAt: skinPoint(event))
    }

    /// A point in skin pixels from the top left, for a point in the view.
    func skinPoint(_ local: NSPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(x: local.x * logicalSize.width / bounds.width,
                       y: (bounds.height - local.y) * logicalSize.height / bounds.height)
    }

    /// The view point for a skin point, for placing pop-up menus.
    func viewPoint(_ skin: CGPoint) -> NSPoint {
        guard logicalSize.width > 0, logicalSize.height > 0 else { return .zero }
        return NSPoint(x: skin.x * bounds.width / logicalSize.width,
                       y: bounds.height - skin.y * bounds.height / logicalSize.height)
    }

    private func skinPoint(_ event: NSEvent) -> CGPoint {
        skinPoint(convert(event.locationInWindow, from: nil))
    }
}

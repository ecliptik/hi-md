import AppKit
import OSLog
import QuartzCore

/// Runs one MilkDrop view: feeds projectM the music once per display refresh while the view can
/// be seen, and moves through the presets. The MilkDrop window has one, and so does the player's
/// artwork when it's showing MilkDrop; each reads the shared audio tap only while started.
@MainActor
final class MilkDropDriver: NSObject {
    private enum Key {
        static let presetDuration = "milkdrop.presetDuration"
    }

    /// How long each preset plays, in seconds.
    static let durations: [Double] = [15, 30, 60, 120]

    let canvas: MilkDropCanvas
    let library = MilkDropPresetLibrary()
    private(set) var isLocked = false
    /// Called after a different preset is loaded, or the lock changes.
    var onPresetChange: (() -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var sampleRate: Double = 44_100
    private let samples = UnsafeMutableBufferPointer<Float>.allocate(capacity: 4096)
    private let scratch = UnsafeMutableBufferPointer<Float>.allocate(capacity: 4096)
    private var isTapAttached = false
    private var failuresInARow = 0

    var presetDuration: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.presetDuration)
            return stored > 0 ? stored : 30
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.presetDuration)
            canvas.presetDuration = newValue
        }
    }

    var presetName: String? { library.current?.deletingPathExtension().lastPathComponent }
    var isRunning: Bool { displayLink != nil }

    init(frame: NSRect) {
        canvas = MilkDropCanvas(frame: frame)
        samples.initialize(repeating: 0)
        scratch.initialize(repeating: 0)
        super.init()
        canvas.presetDuration = presetDuration
        canvas.presetSwitchRequested = { [weak self] hardCut in
            MainActor.assumeIsolated { self?.presetTimeIsUp(hardCut: hardCut) }
        }
        canvas.presetFailed = { [weak self] path, message in
            MainActor.assumeIsolated { self?.presetFailed(path: path, message: message) }
        }
    }

    // MARK: - Running

    /// Attaches to the audio and starts drawing; the first preset loads now if none has.
    func start() {
        if !isTapAttached {
            VisualizerTap.shared.attach()
            isTapAttached = true
        }
        if displayLink == nil {
            let link = canvas.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTick = CACurrentMediaTime()
        }
        if library.current == nil {
            // Another driver may have changed the preset folder since this one last looked.
            library.reload()
            load(library.next(), smooth: false)
        }
        if !canvas.isReady {
            Logger.ui.error("MilkDrop: projectM didn't start; the view stays black")
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if isTapAttached {
            VisualizerTap.shared.detach()
            isTapAttached = false
        }
    }

    /// Feeds projectM the audio played since the last frame, then draws.
    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - lastTick
        lastTick = now
        guard let window = canvas.window, window.occlusionState.contains(.visible), !canvas.isHiddenOrHasHiddenAncestor else {
            return
        }
        let count = min(samples.count, max(64, Int(elapsed * sampleRate)))
        let slice = UnsafeMutableBufferPointer(rebasing: samples[0..<count])
        if let rate = VisualizerTap.shared.readMix(into: slice, scratch: scratch), let base = slice.baseAddress {
            sampleRate = rate
            canvas.addMonoSamples(base, count: UInt(count))
        }
        canvas.renderFrame()
    }

    // MARK: - Presets

    func nextPreset(smooth: Bool = true) { load(library.next(), smooth: smooth) }
    func previousPreset() { load(library.previous(), smooth: true) }

    func toggleLock() {
        isLocked.toggle()
        onPresetChange?()
    }

    func chooseFolder() {
        if library.chooseFolder() { load(library.next(), smooth: false) }
    }

    func useBuiltInPresetsOnly() {
        library.forgetFolder()
        load(library.next(), smooth: false)
    }

    func showFolderInFinder() {
        guard let folder = library.folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func load(_ url: URL?, smooth: Bool) {
        if let url { canvas.loadPreset(atPath: url.path, smooth: smooth) }
        onPresetChange?()
    }

    private func presetTimeIsUp(hardCut: Bool) {
        failuresInARow = 0
        guard !isLocked else { return }
        load(library.next(), smooth: !hardCut)
    }

    /// Moves on from a preset projectM couldn't read, but gives up after a run of failures rather
    /// than spinning through a folder of broken files.
    private func presetFailed(path: String, message: String) {
        Logger.ui.info("MilkDrop: \(URL(fileURLWithPath: path).lastPathComponent, privacy: .public) failed: \(message, privacy: .public)")
        failuresInARow += 1
        guard failuresInARow < min(library.presets.count, 25) else { return }
        load(library.next(), smooth: false)
    }
}

/// The view projectM draws into. In the MilkDrop window it takes MilkDrop's keys, double-click
/// for full screen and the preset menu; in the player's artwork it lets clicks through to the
/// artwork, which cycles what it shows.
final class MilkDropCanvas: HMDMilkDropView {
    weak var controller: MilkDropWindowController?

    override var acceptsFirstResponder: Bool { controller != nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        controller == nil ? nil : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.toggleFullScreen(nil) }
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.makeMenu()
    }
}

import AppKit
import Observation
import OSLog
import SwiftSonic

/// Drives the Winamp main window: renders PlayerState through the skin, turns clicks and drags
/// into PlayerService calls, and runs the marquee, the paused blink and the visualiser only
/// while the window is on screen.
final class WinampMainWindowController: NSObject, NSWindowDelegate, WinampMainViewDelegate {
    /// What the window asks of Winamp mode as a whole.
    struct Actions {
        var close: () -> Void
        var chooseSkin: () -> Void
        var useDefaultSkin: () -> Void
        var isUsingDefaultSkin: () -> Bool
        var showFolderBrowser: () -> Void
    }

    private struct SliderDrag {
        let control: WinampMainControl
        let grabOffset: Double
        var fraction: Double
    }

    private struct TrackInfo {
        let bitRate: Int?
        let samplingRate: Int?
        let channelCount: Int?
    }

    let window: WinampWindow
    private let view: WinampMainView
    private let container: AppContainer
    private let preferences: WinampPreferences
    private let actions: Actions
    private let hitMap = WinampMainHitMap.classic
    private let songSource: WinampSubsonicSource

    private var player: PlayerState { container.playerState }

    // Interaction
    private var trackedButton: WinampMainControl?
    private var pressed: WinampMainControl?
    private var slider: SliderDrag?

    // Display
    private var volume: Double
    /// Visual only: the engine has no balance control.
    private var balance: Double = 0
    /// Stop is a pause back at the start, shown as stopped until playback starts again.
    private var isStopped = false
    private var lastWantsPlayback = false
    private var lastTitle = ""
    private var marqueeStep = 0
    private var marqueeTimer: Timer?
    private var blinkOn = true
    private var blinkTimer: Timer?
    private var isActive = false
    private var isObserving = false

    // Visualiser
    private var visualizer: PlaybackVisualizer?
    private var visualizerTimer: Timer?
    private var peaks = WinampPeakMarkers()
    private var picture = WinampVisualizerPicture.off

    // kbps and kHz
    private var trackInfo: [String: TrackInfo] = [:]
    private var trackInfoTask: Task<Void, Never>?
    private var trackInfoID: String?

    // Volume changes are sent one at a time, newest wins.
    private var pendingVolume: Float?
    private var volumeTask: Task<Void, Never>?

    init(container: AppContainer, skin: WinampSkin, preferences: WinampPreferences, actions: Actions) {
        self.container = container
        self.preferences = preferences
        self.actions = actions
        songSource = WinampSubsonicSource(serverService: container.serverService)
        volume = Double(container.playbackPreferences.restoredVolume)
        view = WinampMainView(skin: skin)
        window = WinampWindow(contentSize: WinampMainLayout.size)
        super.init()
        window.contentView = view
        window.delegate = self
        window.closeHandler = actions.close
        view.delegate = self
        applyWindowOptions()
    }

    // MARK: Lifecycle

    func show() {
        placeWindow()
        isObserving = true
        lastWantsPlayback = player.wantsPlayback
        updateTrackInfo()
        observePlayer()
        window.makeKeyAndOrderFront(nil)
        updateActivity()
    }

    /// Stops every timer, detaches the visualiser and hides the window.
    func tearDown() {
        isObserving = false
        stopVisualizer()
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
        trackInfoTask?.cancel()
        window.delegate = nil
        window.orderOut(nil)
    }

    func setSkin(_ skin: WinampSkin) {
        view.skin = skin
    }

    // MARK: Window options

    private var scale: CGFloat { preferences.isDoubleSize ? 2 : 1 }

    private func applyWindowOptions() {
        window.level = preferences.isAlwaysOnTop ? .floating : .normal
    }

    /// The saved spot, or centred on the main screen when it's new or no longer on any screen.
    private func placeWindow() {
        let size = CGSize(width: WinampMainLayout.size.width * scale, height: WinampMainLayout.size.height * scale)
        var topLeft = preferences.windowTopLeft
        if let saved = topLeft {
            let titleBar = CGRect(x: saved.x, y: saved.y - 14 * scale, width: size.width, height: 14 * scale)
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(titleBar) }) { topLeft = nil }
        }
        let origin: CGPoint
        if let topLeft {
            origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        } else {
            let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            origin = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        }
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func toggleDoubleSize() {
        let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        preferences.isDoubleSize.toggle()
        let size = CGSize(width: WinampMainLayout.size.width * scale, height: WinampMainLayout.size.height * scale)
        window.setFrame(CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        window.invalidateShadow()
        refresh()
    }

    private func toggleAlwaysOnTop() {
        preferences.isAlwaysOnTop.toggle()
        applyWindowOptions()
        refresh()
    }

    private func setVisualizerMode(_ mode: WinampVisualizerMode) {
        preferences.visualizerMode = mode
        peaks.reset()
        updateActivity()
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        preferences.windowTopLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        isActive = true
        refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        isActive = false
        refresh()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateActivity()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        updateActivity()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        updateActivity()
    }

    private var isOnScreen: Bool {
        isObserving && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    /// The visualiser runs only while it can be seen and something plays. Loading between songs
    /// counts as playing, so the tap isn't detached and reattached at every track change.
    private var shouldVisualize: Bool {
        isOnScreen && preferences.visualizerMode != .off && player.wantsPlayback && !isStopped
    }

    /// Starts or stops the visualiser and timers to match what is on screen.
    private func updateActivity() {
        if shouldVisualize { startVisualizer() } else { stopVisualizer() }
        refresh()
    }

    // MARK: Player observation

    /// Every PlayerState property read while rendering is tracked; any change renders again.
    private func observePlayer() {
        guard isObserving else { return }
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.playerDidChange() }
        }
    }

    private func playerDidChange() {
        guard isObserving else { return }
        let wants = player.wantsPlayback
        if wants && !lastWantsPlayback { isStopped = false }
        lastWantsPlayback = wants
        updateTrackInfo()
        let visualize = shouldVisualize
        if visualize != (visualizer != nil) {
            if visualize { startVisualizer() } else { stopVisualizer() }
        }
        observePlayer()
    }

    // MARK: Rendering

    private func refresh() {
        let fullTitle = titleText()
        if fullTitle != lastTitle {
            lastTitle = fullTitle
            marqueeStep = 0
        }
        view.state = makeState(title: fullTitle)
        updateTimers(title: fullTitle)
    }

    private var displayedPlayback: WinampMainDisplayState.Playback {
        if isStopped { return .stopped }
        switch player.playbackState {
        case .playing, .loading: return .playing
        case .paused: return player.currentTrack == nil && player.currentRadio == nil ? .stopped : .paused
        case .idle, .error: return .stopped
        }
    }

    private func makeState(title fullTitle: String) -> WinampMainDisplayState {
        var state = WinampMainDisplayState()
        let playback = displayedPlayback
        state.isActive = isActive
        state.playback = playback
        state.isBuffering = player.playbackState == .loading || player.waitingReason != nil
        if playback != .stopped, playback == .playing || blinkOn {
            state.time = WinampTimeDisplay.make(position: player.position, duration: player.duration, mode: preferences.timeMode)
        }
        state.title = WinampMarquee.visibleText(fullTitle, step: marqueeStep)
        if playback != .stopped, let id = player.currentTrack?.id, let info = trackInfo[id] {
            let streamLimit = player.currentTrack?.isDownloaded == true ? nil : container.streamSettings.currentQuality.subsonicMaxBitRate
            state.kbps = WinampTrackInfoFormat.kbps(WinampTrackInfoFormat.effectiveBitRate(file: info.bitRate, maxBitRate: streamLimit))
            state.khz = WinampTrackInfoFormat.khz(info.samplingRate)
            if let channels = info.channelCount {
                state.channels = channels == 1 ? .mono : .stereo
            }
        }
        state.volume = slider?.control == .volume ? slider?.fraction ?? volume : volume
        state.balance = slider?.control == .balance ? WinampBalance.balance(for: slider?.fraction ?? 0.5) : balance
        if let slider, slider.control == .seek {
            state.seekFraction = slider.fraction
        } else if playback != .stopped, !player.isLiveStream, player.duration > 0 {
            state.seekFraction = WinampSliderGeometry.clamp(player.position / player.duration)
        }
        state.pressed = pressed
        state.isShuffleOn = player.isShuffled
        state.isRepeatOn = player.repeatMode != .off
        state.isAlwaysOnTop = preferences.isAlwaysOnTop
        state.isDoubleSize = preferences.isDoubleSize
        let mode = preferences.visualizerMode
        state.visualizer = mode == .off ? .off : (visualizer == nil ? WinampVisualizerPicture(mode: mode) : picture)
        return state
    }

    /// The marquee text, or the value being dragged while a slider is held.
    private func titleText() -> String {
        if let slider {
            switch slider.control {
            case .seek: return WinampSliderMessage.seek(fraction: slider.fraction, duration: player.duration)
            case .volume: return WinampSliderMessage.volume(slider.fraction)
            case .balance: return WinampSliderMessage.balance(WinampBalance.balance(for: slider.fraction))
            default: break
            }
        }
        if let radio = player.currentRadio { return radio.name }
        if let track = player.currentTrack {
            return WinampMarquee.songTitle(artist: track.artist, title: track.title,
                                           duration: track.duration > 0 ? track.duration : player.duration)
        }
        return "Minidisc"
    }

    private func updateTimers(title: String) {
        let scrolls = isOnScreen && slider == nil && WinampMarquee.scrolls(title)
        if scrolls, marqueeTimer == nil {
            marqueeTimer = repeatingTimer(interval: WinampMarquee.stepInterval) { controller in
                controller.marqueeStep = WinampMarquee.nextStep(after: controller.marqueeStep, text: controller.lastTitle)
                controller.refresh()
            }
        } else if !scrolls, let timer = marqueeTimer {
            timer.invalidate()
            marqueeTimer = nil
        }

        let blinks = isOnScreen && displayedPlayback == .paused
        if blinks, blinkTimer == nil {
            blinkTimer = repeatingTimer(interval: .milliseconds(500)) { controller in
                controller.blinkOn.toggle()
                controller.refresh()
            }
        } else if !blinks, let timer = blinkTimer {
            timer.invalidate()
            blinkTimer = nil
            blinkOn = true
        }
    }

    private func repeatingTimer(interval: Duration,
                                _ tick: @escaping @MainActor @Sendable (WinampMainWindowController) -> Void) -> Timer {
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                tick(self)
            }
        }
        timer.tolerance = seconds / 10
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: Visualiser

    private func startVisualizer() {
        guard visualizer == nil else { return }
        let visualizer = PlaybackVisualizer(configuration: .winamp)
        visualizer.start()
        self.visualizer = visualizer
        visualizerTimer = repeatingTimer(interval: .milliseconds(1000 / PlaybackVisualizer.framesPerSecond)) { controller in
            controller.visualizerTick()
        }
    }

    /// Detaches the tap so nothing is copied or analysed while the window can't be seen.
    private func stopVisualizer() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        visualizer?.stop()
        visualizer = nil
        peaks.reset()
        picture = .off
    }

    private func visualizerTick() {
        guard let visualizer else { return }
        let frame = visualizer.latestFrame
        picture = WinampVisualizerPicture(
            mode: preferences.visualizerMode,
            bars: frame.spectrum,
            peaks: peaks.update(with: frame.spectrum),
            waveform: frame.waveform
        )
        refresh()
    }

    // MARK: kbps and kHz

    /// Looks up the playing song's bitrate, sample rate and channels once per song. Local files
    /// and radio have none to show.
    private func updateTrackInfo() {
        guard let track = player.currentTrack, !track.isLocalFile, player.currentRadio == nil else { return }
        guard trackInfo[track.id] == nil, trackInfoID != track.id else { return }
        trackInfoID = track.id
        trackInfoTask?.cancel()
        let source = songSource
        let id = track.id
        trackInfoTask = Task { [weak self] in
            guard let song = try? await source.song(id: id), !Task.isCancelled else { return }
            self?.trackInfo[id] = TrackInfo(bitRate: song.bitRate, samplingRate: song.samplingRate, channelCount: song.channelCount)
            self?.refresh()
        }
    }

    // MARK: Mouse and keys

    func mainView(_ view: WinampMainView, mouseDownAt point: CGPoint, event: NSEvent) {
        guard let control = hitMap.control(at: point) else { return }
        switch control {
        case .titleBar:
            window.performDrag(with: event)
        case .seek:
            guard displayedPlayback != .stopped, !player.isLiveStream, player.duration > 0 else { return }
            beginSlider(.seek, geometry: .seek, current: WinampSliderGeometry.clamp(player.position / player.duration), at: point)
        case .volume:
            beginSlider(.volume, geometry: .volume, current: volume, at: point)
        case .balance:
            beginSlider(.balance, geometry: .balance, current: WinampBalance.fraction(for: balance), at: point)
        case .time:
            preferences.timeMode = preferences.timeMode.toggled
            refresh()
        case .visualizer:
            setVisualizerMode(preferences.visualizerMode.next)
        case .songTitle:
            break
        default:
            trackedButton = control
            pressed = control
            refresh()
        }
    }

    func mainView(_ view: WinampMainView, mouseDraggedTo point: CGPoint) {
        if var drag = slider, let geometry = geometry(for: drag.control) {
            drag.fraction = geometry.fraction(pointerX: point.x, grabOffset: drag.grabOffset)
            slider = drag
            if drag.control == .volume { sendVolume(drag.fraction) }
            refresh()
        } else if let trackedButton {
            let inside = hitMap.control(at: point) == trackedButton
            if (pressed != nil) != inside {
                pressed = inside ? trackedButton : nil
                refresh()
            }
        }
    }

    func mainView(_ view: WinampMainView, mouseUpAt point: CGPoint) {
        if let drag = slider {
            slider = nil
            pressed = nil
            finishSlider(drag)
            refresh()
        } else if let button = trackedButton {
            trackedButton = nil
            pressed = nil
            refresh()
            if hitMap.control(at: point) == button {
                perform(button, at: point)
            }
        }
    }

    func mainView(_ view: WinampMainView, keyDown event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        // Winamp's keys along the bottom row of the keyboard.
        let control: WinampMainControl? = switch key {
        case "z": .previous
        case "x": .play
        case "c": .pause
        case "v": .stop
        case "b": .next
        case "l": .eject
        default: nil
        }
        guard let control else { return false }
        perform(control, at: .zero)
        return true
    }

    private func geometry(for control: WinampMainControl) -> WinampSliderGeometry? {
        switch control {
        case .seek: .seek
        case .volume: .volume
        case .balance: .balance
        default: nil
        }
    }

    private func beginSlider(_ control: WinampMainControl, geometry: WinampSliderGeometry, current: Double, at point: CGPoint) {
        let grab = geometry.grabOffset(pointerX: point.x, currentFraction: current)
        let fraction = geometry.fraction(pointerX: point.x, grabOffset: grab)
        slider = SliderDrag(control: control, grabOffset: grab, fraction: fraction)
        pressed = control
        if control == .volume { sendVolume(fraction) }
        refresh()
    }

    private func finishSlider(_ drag: SliderDrag) {
        switch drag.control {
        case .seek:
            let target = drag.fraction * player.duration
            Task { await container.playerService.seek(to: target) }
        case .volume:
            volume = drag.fraction
            sendVolume(drag.fraction)
        case .balance:
            balance = WinampBalance.balance(for: drag.fraction)
        default:
            break
        }
    }

    private func sendVolume(_ fraction: Double) {
        volume = fraction
        pendingVolume = Float(fraction)
        guard volumeTask == nil else { return }
        let service = container.playerService
        volumeTask = Task { [weak self] in
            while let value = self?.pendingVolume {
                self?.pendingVolume = nil
                await service.setVolume(value)
            }
            self?.volumeTask = nil
        }
    }

    // MARK: Actions

    private func perform(_ control: WinampMainControl, at point: CGPoint) {
        let service = container.playerService
        let toasts = container.toastService
        switch control {
        case .previous:
            Task { await toasts.perform { try await service.skipToPrevious() } }
        case .next:
            Task { await toasts.perform { try await service.skipToNext() } }
        case .play:
            play()
        case .pause:
            if isStopped { return }
            if player.wantsPlayback {
                Task { await service.pause() }
            } else if player.playbackState == .paused {
                Task { await service.resume() }
            }
        case .stop:
            stop()
        case .eject:
            actions.showFolderBrowser()
        case .shuffle:
            Task { await service.toggleShuffle() }
        case .repeatToggle:
            let mode: RepeatMode = player.repeatMode == .off ? .all : .off
            Task { await service.setRepeatMode(mode) }
        case .close:
            actions.close()
        case .minimize:
            window.miniaturize(nil)
        case .options, .clutter(.options):
            showMenu(contextMenu(for: view), at: point)
        case .clutter(.alwaysOnTop):
            toggleAlwaysOnTop()
        case .clutter(.doubleSize):
            toggleDoubleSize()
        case .clutter(.visualizer):
            showMenu(visualizerMenu(), at: point)
        case .shade, .equalizer, .playlist, .clutter(.info):
            // Windowshade, the equaliser and the playlist window come in later phases.
            break
        case .titleBar, .time, .visualizer, .songTitle, .volume, .balance, .seek:
            break
        }
    }

    /// Winamp's Play: restarts a playing song, resumes a paused or stopped one, starts the queue
    /// when nothing is loaded, and opens the browser when the queue is empty.
    private func play() {
        let service = container.playerService
        let toasts = container.toastService
        let queue = player.queue
        let startIndex = min(max(player.currentIndex, 0), max(queue.count - 1, 0))
        let wasStopped = isStopped
        isStopped = false
        refresh()
        if player.currentTrack == nil || isErrorState {
            guard !queue.isEmpty else {
                actions.showFolderBrowser()
                return
            }
            Task { await toasts.perform { try await service.play(tracks: queue, startIndex: startIndex) } }
        } else if player.wantsPlayback && !wasStopped {
            Task { await service.seek(to: 0) }
        } else {
            Task { await service.resume() }
        }
    }

    private var isErrorState: Bool {
        if case .error = player.playbackState { return true }
        return false
    }

    /// PlayerService's own stop clears the queue, which Winamp's Stop never does: this pauses and
    /// returns to the start instead, and the window shows stopped until playback starts again.
    private func stop() {
        guard player.currentTrack != nil, !isStopped else { return }
        isStopped = true
        lastWantsPlayback = false
        updateActivity()
        let service = container.playerService
        let isLive = player.isLiveStream
        Task {
            await service.pause()
            if !isLive { await service.seek(to: 0) }
        }
    }

    // MARK: Menus

    func contextMenu(for view: WinampMainView) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "Load Skin…")) { $0.actions.chooseSkin() })
        menu.addItem(item(String(localized: "Default Skin"), isOn: actions.isUsingDefaultSkin()) { $0.actions.useDefaultSkin() })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Always on Top"), isOn: preferences.isAlwaysOnTop) { $0.toggleAlwaysOnTop() })
        menu.addItem(item(String(localized: "Double Size"), isOn: preferences.isDoubleSize) { $0.toggleDoubleSize() })
        let visualizer = NSMenuItem(title: String(localized: "Visualizer"), action: nil, keyEquivalent: "")
        visualizer.submenu = visualizerMenu()
        menu.addItem(visualizer)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Close")) { $0.actions.close() })
        return menu
    }

    private func visualizerMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Visualizer"))
        for (mode, title) in [(WinampVisualizerMode.spectrum, String(localized: "Spectrum Analyzer")),
                              (.oscilloscope, String(localized: "Oscilloscope")),
                              (.off, String(localized: "Off"))] {
            menu.addItem(item(title, isOn: preferences.visualizerMode == mode) { $0.setVisualizerMode(mode) })
        }
        return menu
    }

    private func showMenu(_ menu: NSMenu?, at point: CGPoint) {
        guard let menu else { return }
        let location = NSPoint(x: point.x * view.bounds.width / WinampMainLayout.size.width,
                               y: view.bounds.height - point.y * view.bounds.height / WinampMainLayout.size.height)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    private func item(_ title: String, isOn: Bool? = nil,
                      _ action: @escaping (WinampMainWindowController) -> Void) -> NSMenuItem {
        let target = WinampMenuAction { [weak self] in
            guard let self else { return }
            action(self)
        }
        let item = NSMenuItem(title: title, action: #selector(WinampMenuAction.run(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        if let isOn { item.state = isOn ? .on : .off }
        return item
    }
}

/// The target of a Winamp menu item: runs a closure. The item keeps it alive as its represented object.
private final class WinampMenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) {
        handler()
    }
}

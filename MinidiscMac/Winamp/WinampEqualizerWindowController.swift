import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

/// Drives the Winamp equaliser window: ON, AUTO, the preamp and ten band sliders bound to the
/// app's equaliser, the response curve, and the Presets menu with Winamp `.eqf` import and export.
final class WinampEqualizerWindowController: NSObject, NSWindowDelegate, WinampSurfaceDelegate, WinampManagedWindow {
    private struct SliderDrag {
        let control: WinampEqualizerControl
        let grabOffset: CGFloat
        var value: Float
    }

    let kind = WinampPreferences.Window.equalizer
    let window: WinampWindow
    private let view: WinampSurfaceView
    private let model: any WinampEqualizerModel
    private weak var host: WinampWindowHost?
    private let preferences: WinampPreferences
    private var skin: WinampSkin
    private var sprites: WinampSpriteCache
    private var isShaded: Bool
    private var isActive = false
    private var isObserving = false
    private var pressed: WinampEqualizerControl?
    private var trackedButton: WinampEqualizerControl?
    private var slider: SliderDrag?
    private var isDraggingWindow = false

    init(model: any WinampEqualizerModel, skin: WinampSkin, host: WinampWindowHost) {
        self.model = model
        self.host = host
        preferences = host.preferences
        self.skin = skin
        sprites = WinampSpriteCache(skin: skin)
        isShaded = host.preferences.isShaded(.equalizer) && WinampEqualizerRenderer.hasShadeSprites(skin)
        view = WinampSurfaceView(logicalSize: WinampEqualizerLayout.size, accessibilityLabel: String(localized: "Miniamp Equalizer"))
        window = WinampWindow(contentSize: WinampEqualizerLayout.size)
        super.init()
        window.title = String(localized: "Miniamp Equalizer")
        window.contentView = view
        window.delegate = self
        window.closeHandler = { [weak host] in host?.close(.equalizer) }
        view.delegate = self
        view.logicalSize = logicalSize
    }

    var logicalSize: CGSize { isShaded ? WinampEqualizerLayout.shadeSize : WinampEqualizerLayout.size }
    private var scale: CGFloat { host?.scale ?? 1 }
    private var hasShade: Bool { WinampEqualizerRenderer.hasShadeSprites(skin) }

    // MARK: WinampManagedWindow

    func show(at topLeft: CGPoint) {
        let size = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        window.setFrame(CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        isObserving = true
        observeModel()
        window.orderFront(nil)
    }

    func tearDown() {
        isObserving = false
        window.delegate = nil
        window.orderOut(nil)
    }

    func setSkin(_ skin: WinampSkin) {
        self.skin = skin
        sprites = WinampSpriteCache(skin: skin)
        if isShaded, !hasShade { toggleShade() }
        refresh()
    }

    func refresh() {
        view.logicalSize = logicalSize
        view.refresh()
    }

    /// Every model property read while rendering is tracked; any change renders again.
    private func observeModel() {
        guard isObserving else { return }
        withObservationTracking {
            _ = model.isEnabled
            _ = model.gains
            _ = model.preamp
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observeModel()
            }
        }
    }

    private var state: WinampEqualizerDisplayState {
        var state = WinampEqualizerDisplayState()
        state.isActive = isActive
        state.isShaded = isShaded
        state.isOn = model.isEnabled
        state.isAuto = preferences.isEqualizerAuto
        state.preamp = model.preamp
        state.gains = WinampEqualizerBands.sliderGains(fromEngine: model.gains)
        if let slider {
            switch slider.control {
            case .preamp: state.preamp = slider.value
            case .band(let index) where state.gains.indices.contains(index): state.gains[index] = slider.value
            default: break
            }
        }
        state.pressed = pressed
        return state
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        isActive = true
        refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        isActive = false
        refresh()
    }

    // MARK: WinampSurfaceDelegate

    func surfaceImage(_ view: WinampSurfaceView, pixelScale: CGFloat) -> CGImage? {
        WinampEqualizerRenderer.render(state, skin: skin, sprites: sprites, scale: pixelScale)
    }

    private func control(at point: CGPoint) -> WinampEqualizerControl? {
        isShaded ? WinampEqualizerLayout.shadeControl(at: point) : WinampEqualizerLayout.control(at: point, hasShade: hasShade)
    }

    func surface(_ view: WinampSurfaceView, mouseDownAt point: CGPoint, event: NSEvent) {
        guard let control = control(at: point) else { return }
        switch control {
        case .titleBar:
            if event.clickCount == 2, hasShade {
                toggleShade()
            } else {
                isDraggingWindow = true
                host?.beginDrag(.equalizer)
            }
        case .preamp, .band:
            let rect = control == .preamp ? WinampEqualizerLayout.preamp : WinampEqualizerLayout.band(bandIndex(control) ?? 0)
            let current = value(of: control)
            let grab = WinampEqualizerSlider.grabOffset(pointerY: point.y - rect.minY, currentDB: current)
            let value = WinampEqualizerSlider.dB(pointerY: point.y - rect.minY, grabOffset: grab)
            slider = SliderDrag(control: control, grabOffset: grab, value: value)
            pressed = control
            commit(value, for: control)
        case .close, .shade, .on, .auto, .presets:
            trackedButton = control
            pressed = control
            refresh()
        }
    }

    func surface(_ view: WinampSurfaceView, mouseDraggedTo point: CGPoint, event: NSEvent) {
        if isDraggingWindow {
            host?.continueDrag()
        } else if var drag = slider {
            let rect = drag.control == .preamp ? WinampEqualizerLayout.preamp : WinampEqualizerLayout.band(bandIndex(drag.control) ?? 0)
            drag.value = WinampEqualizerSlider.dB(pointerY: point.y - rect.minY, grabOffset: drag.grabOffset)
            slider = drag
            commit(drag.value, for: drag.control)
        } else if let trackedButton {
            let inside = control(at: point) == trackedButton
            if (pressed != nil) != inside {
                pressed = inside ? trackedButton : nil
                refresh()
            }
        }
    }

    func surface(_ view: WinampSurfaceView, mouseUpAt point: CGPoint, event: NSEvent) {
        if isDraggingWindow {
            isDraggingWindow = false
            host?.endDrag()
        } else if slider != nil {
            slider = nil
            pressed = nil
            refresh()
        } else if let button = trackedButton {
            trackedButton = nil
            pressed = nil
            refresh()
            if control(at: point) == button { perform(button) }
        }
    }

    func surface(_ view: WinampSurfaceView, scrollWheel event: NSEvent) {}

    func surface(_ view: WinampSurfaceView, keyDown event: NSEvent) -> Bool { false }

    func surface(_ view: WinampSurfaceView, menuAt point: CGPoint) -> NSMenu? {
        presetsMenu()
    }

    // MARK: Values

    private func bandIndex(_ control: WinampEqualizerControl) -> Int? {
        if case .band(let index) = control { return index }
        return nil
    }

    private func value(of control: WinampEqualizerControl) -> Float {
        switch control {
        case .preamp: return model.preamp
        case .band(let index):
            let gains = WinampEqualizerBands.sliderGains(fromEngine: model.gains)
            return gains.indices.contains(index) ? gains[index] : 0
        default: return 0
        }
    }

    /// Sends a slider's value to the equaliser as it moves.
    private func commit(_ value: Float, for control: WinampEqualizerControl) {
        switch control {
        case .preamp:
            model.setPreamp(value)
        case .band(let index):
            guard let band = WinampEqualizerBands.engineBand(forSlider: index) else { return }
            model.setGain(value, band: band)
        default:
            return
        }
        refresh()
    }

    private func perform(_ control: WinampEqualizerControl) {
        switch control {
        case .close:
            host?.close(.equalizer)
        case .shade:
            toggleShade()
        case .on:
            model.isEnabled.toggle()
            refresh()
        case .auto:
            preferences.isEqualizerAuto.toggle()
            if preferences.isEqualizerAuto { WinampMode.shared.equalizerAutoDidChange() }
            refresh()
        case .presets:
            let menu = presetsMenu()
            menu.popUp(positioning: nil, at: view.viewPoint(CGPoint(x: WinampEqualizerLayout.presets.minX,
                                                                    y: WinampEqualizerLayout.presets.maxY)), in: view)
        case .titleBar, .preamp, .band:
            break
        }
    }

    private func toggleShade() {
        guard hasShade || isShaded else { return }
        isShaded.toggle()
        preferences.setShaded(isShaded, .equalizer)
        view.logicalSize = logicalSize
        host?.resize(.equalizer, to: CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale))
        refresh()
    }

    // MARK: Presets

    private func presetsMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Presets"))
        let load = NSMenuItem(title: String(localized: "Load"), action: nil, keyEquivalent: "")
        let loadMenu = NSMenu()
        for preset in EqualizerPreset.allCases {
            loadMenu.addItem(winampMenuItem(String(localized: preset.title)) { [weak self] in self?.apply(preset) })
        }
        let saved = preferences.equalizerPresets
        if !saved.isEmpty {
            loadMenu.addItem(.separator())
            for preset in saved {
                loadMenu.addItem(winampMenuItem(preset.name) { [weak self] in self?.apply(preset) })
            }
        }
        load.submenu = loadMenu
        menu.addItem(load)
        menu.addItem(winampMenuItem(String(localized: "Save Preset…")) { [weak self] in self?.savePreset() })
        if !saved.isEmpty {
            let delete = NSMenuItem(title: String(localized: "Delete Preset"), action: nil, keyEquivalent: "")
            let deleteMenu = NSMenu()
            for preset in saved {
                deleteMenu.addItem(winampMenuItem(preset.name) { [weak self] in self?.preferences.deleteEqualizerPreset(named: preset.name) })
            }
            delete.submenu = deleteMenu
            menu.addItem(delete)
        }
        menu.addItem(.separator())
        menu.addItem(winampMenuItem(String(localized: "Import EQF File…")) { [weak self] in self?.importEQF() })
        menu.addItem(winampMenuItem(String(localized: "Export EQF File…")) { [weak self] in self?.exportEQF() })
        menu.addItem(.separator())
        menu.addItem(winampMenuItem(String(localized: "Reset to Flat")) { [weak self] in self?.apply(.flat) })
        return menu
    }

    private func apply(_ preset: EqualizerPreset) {
        model.apply(preset)
        refresh()
    }

    private func apply(_ preset: WinampEqualizerPreset) {
        for (slider, gain) in preset.gains.enumerated() {
            guard let band = WinampEqualizerBands.engineBand(forSlider: slider) else { continue }
            model.setGain(gain, band: band)
        }
        model.setPreamp(preset.preamp)
        refresh()
    }

    private var currentPreset: WinampEqualizerPreset {
        WinampEqualizerPreset(name: "", preamp: model.preamp, gains: model.gains)
    }

    private func savePreset() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Preset")
        alert.informativeText = String(localized: "Name this equalizer curve.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = String(localized: "Preset Name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var preset = currentPreset
        preset.name = name
        preferences.saveEqualizerPreset(preset)
    }

    private static var eqfType: UTType { UTType(filenameExtension: "eqf") ?? .data }

    private func importEQF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.eqfType, UTType(filenameExtension: "q1") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= WinampEQF.maximumFileSize, let data = try? Data(contentsOf: url),
              let presets = WinampEQF.decode(data), let first = presets.first else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Import Preset")
            alert.informativeText = String(localized: "This file isn't a Winamp equalizer preset.")
            alert.runModal()
            return
        }
        let fallbackName = url.deletingPathExtension().lastPathComponent
        for var preset in presets {
            if preset.name.isEmpty { preset.name = fallbackName }
            preferences.saveEqualizerPreset(preset)
        }
        apply(first)
    }

    private func exportEQF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.eqfType]
        panel.nameFieldStringValue = "Hi-MD.eqf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var preset = currentPreset
        preset.name = url.deletingPathExtension().lastPathComponent
        do {
            try WinampEQF.encode([preset]).write(to: url, options: .atomic)
        } catch {
            Logger.ui.error("Winamp: couldn't export the EQ preset: \(String(describing: error), privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }
}

/// A menu item that runs a closure. The item keeps the closure's target alive as its
/// represented object.
func winampMenuItem(_ title: String, isOn: Bool? = nil, isEnabled: Bool = true,
                    handler: @escaping () -> Void) -> NSMenuItem {
    let target = WinampMenuTarget(handler)
    let item = NSMenuItem(title: title, action: #selector(WinampMenuTarget.run(_:)), keyEquivalent: "")
    item.target = target
    item.representedObject = target
    item.isEnabled = isEnabled
    if let isOn { item.state = isOn ? .on : .off }
    return item
}

private final class WinampMenuTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) {
        handler()
    }
}

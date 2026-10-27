import AppKit
import Observation
import SwiftUI

/// Shows and hides a player surface's controls (and its window's traffic lights) by the idle rule
/// in `PlayerChromeVisibility`: in with the pointer, a click or a key, out 2.5 seconds later,
/// held while VoiceOver runs, a control has keyboard focus, a menu or popover is open, or a scrub
/// is under way.
@Observable
@MainActor
final class MacPlayerChrome {
    private(set) var isVisible = false
    @ObservationIgnored private var state = PlayerChromeVisibility()
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The pointer moved over the surface, or a click or key press happened there.
    func registerActivity() {
        state.registerActivity(at: now)
        refresh()
    }

    func pointerExited() {
        state.pointerExited()
        refresh()
    }

    func set(_ pin: PlayerChromeVisibility.Pin, _ isOn: Bool) {
        guard state.pins.contains(pin) != isOn else { return }
        state.set(pin, isOn, at: now)
        refresh()
    }

    /// A menu began tracking somewhere in the app: it holds the controls only when it came from
    /// them, that is while they're showing.
    func menuBeganTracking() {
        if isVisible { set(.menu, true) }
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func refresh() {
        let visible = state.isVisible(at: now)
        if visible != isVisible { isVisible = visible }
        // One timer at a time: it sleeps to the deadline, which more activity pushes back.
        guard hideTask == nil, state.hideDeadline(after: now) != nil else { return }
        hideTask = Task { [weak self] in
            while let self, let deadline = self.state.hideDeadline(after: self.now) {
                try? await Task.sleep(for: .seconds(max(deadline - self.now, 0.05)))
                if Task.isCancelled { return }
            }
            self?.hideTask = nil
            self?.refresh()
        }
    }
}

/// Feeds a surface's chrome: the pointer moving is activity, and VoiceOver, menus and scrubbing
/// hold it. Keyboard focus is fed by the surface, which knows its own controls.
struct MacPlayerChromeTracking: ViewModifier {
    let chrome: MacPlayerChrome
    /// Whether the surface tracks at all; outside full screen Now Playing keeps its buttons.
    var isEnabled = true

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                guard isEnabled else { return }
                switch phase {
                case .active: chrome.registerActivity()
                case .ended: chrome.pointerExited()
                }
            }
            .onChange(of: voiceOverEnabled, initial: true) { _, running in chrome.set(.voiceOver, running) }
            .onChange(of: playback.state.lyricsClock.isScrubbing) { _, scrubbing in chrome.set(.scrubbing, scrubbing) }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                chrome.menuBeganTracking()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                chrome.set(.menu, false)
            }
            .onAppear {
                // A moment of the controls when the surface opens, so they're found.
                if isEnabled { chrome.registerActivity() }
            }
            .onDisappear { chrome.stop() }
    }
}

extension View {
    func playerChromeTracking(_ chrome: MacPlayerChrome, isEnabled: Bool = true) -> some View {
        modifier(MacPlayerChromeTracking(chrome: chrome, isEnabled: isEnabled))
    }

    /// Fades auto-hiding controls in and out. They leave hit testing while hidden, so a click on
    /// the artwork under them doesn't land on an invisible button, but stay in the hierarchy, so
    /// VoiceOver and the keyboard still reach them (which brings them back).
    func playerChromeFade(_ isVisible: Bool, reduceMotion: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isVisible)
    }
}

// MARK: - Glass

enum MacGlass {
    /// Reduce Transparency's fill in place of glass: white glyphs on it are above 12:1.
    static let solidFill = Color(white: 0.16)
    /// The selected toggle's fill in a glass group, where the Music app uses red.
    static let selectedFill = Color.minidiscAccent
    static let selectedGlyph = Color.minidiscAccentText
}

/// Liquid Glass behind a control, or a solid fill with Reduce Transparency. `isShown` false turns
/// the glass to `.identity`, so it dematerialises with the control rather than lingering.
private struct MacGlassBackground<S: Shape>: ViewModifier {
    let shape: S
    var isInteractive = true
    var isShown = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(MacGlass.solidFill, in: shape)
        } else {
            content.glassEffect(isShown ? (isInteractive ? .regular.interactive() : .regular) : .identity, in: shape)
        }
    }
}

extension View {
    func macGlass(in shape: some Shape = Capsule(), interactive: Bool = true, isShown: Bool = true) -> some View {
        modifier(MacGlassBackground(shape: shape, isInteractive: interactive, isShown: isShown))
    }
}

/// `.buttonStyle(.glass)`, or `.glassProminent` tinted with the accent for a toggle that's on; with
/// Reduce Transparency a solid capsule, accent-filled when on.
struct MacGlassButtonStyling: ViewModifier {
    var isProminent = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(MacSolidCapsuleButtonStyle(isProminent: isProminent))
        } else if isProminent {
            content
                .buttonStyle(.glassProminent)
                .tint(MacGlass.selectedFill)
                .foregroundStyle(MacGlass.selectedGlyph)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

private struct MacSolidCapsuleButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isProminent ? MacGlass.selectedGlyph : Color.white)
            .background(isProminent ? MacGlass.selectedFill : MacGlass.solidFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension View {
    func macGlassButton(prominent: Bool = false) -> some View {
        modifier(MacGlassButtonStyling(isProminent: prominent))
    }
}

/// A row of glass buttons that reads as one capsule, the Music app's grouped player buttons. The
/// selected toggle is filled with the accent, and the fill slides between toggles (not with Reduce
/// Motion). Inside a `GlassEffectContainer`, so it and neighbouring glass blend as they come and go.
struct MacGlassGroup<Content: View>: View {
    var isShown = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                content()
            }
            .padding(3)
            .macGlass(in: Capsule(), isShown: isShown)
        }
    }
}

/// One button of a `MacGlassGroup`: a glyph, filled with the accent while `isOn`.
struct MacGlassSegment: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Nil for a plain button, true or false for a toggle.
    var isOn: Bool? = nil
    var side: Double = 28
    /// Shared by a group's toggles, so the accent fill slides from one to the next.
    var selection: Namespace.ID? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: (side * 0.48).rounded(), weight: .semibold))
                .foregroundStyle(isOn == true ? MacGlass.selectedGlyph : Color.white)
                .frame(width: side + 6, height: side)
                .background {
                    if isOn == true {
                        selectedFill
                    }
                }
                .contentShape(Capsule())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isOn.map { $0 ? Text("On") : Text("Off") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
        .help(Text(title))
    }

    @ViewBuilder private var selectedFill: some View {
        if let selection {
            Capsule().fill(MacGlass.selectedFill)
                .matchedGeometryEffect(id: "selection", in: selection)
        } else {
            Capsule().fill(MacGlass.selectedFill)
        }
    }
}

/// A small round glass button: the heart and the menu over the artwork.
struct MacGlassCircleLabel: View {
    let systemImage: String
    var side: Double = 28
    var tint: Color = .white
    var isShown = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: (side * 0.46).rounded(), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .contentShape(Circle())
            .macGlass(in: Circle(), isShown: isShown)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// The soft dark scrim under controls laid over artwork: clear at the top, then dark enough that
/// white text and the secondary white keep 4.5:1 over the brightest artwork. With Reduce
/// Transparency, a solid dark band instead.
struct MacArtworkScrim: View {
    /// How far above the controls the scrim fades in.
    var fadeHeight: Double = 56

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Black over the controls: white text on a white artwork under it is about 7:1, and the
    /// secondary white at 0.78 opacity about 5:1.
    static let controlsOpacity = 0.65
    static let bottomOpacity = 0.82

    var body: some View {
        if reduceTransparency {
            VStack(spacing: 0) {
                Color.clear.frame(height: fadeHeight)
                Color.black.opacity(0.88)
            }
        } else {
            GeometryReader { proxy in
                let height = max(Double(proxy.size.height), 1)
                let start = min(fadeHeight / height, 0.9)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(Self.controlsOpacity * 0.5), location: start * 0.55),
                    .init(color: .black.opacity(Self.controlsOpacity), location: start),
                    .init(color: .black.opacity(Self.bottomOpacity), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

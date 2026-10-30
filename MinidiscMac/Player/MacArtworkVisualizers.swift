import AppKit
import SwiftUI

/// MilkDrop in place of the artwork, with its own projectM and the presets of the MilkDrop
/// window. Clicks go through to the artwork, which moves on to the cover.
struct MacMilkDropArtwork: NSViewRepresentable {
    var cornerRadius: Double

    @MainActor
    final class Coordinator {
        let driver = MilkDropDriver(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MilkDropCanvas {
        let canvas = context.coordinator.driver.canvas
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = cornerRadius
        canvas.layer?.cornerCurve = .continuous
        canvas.layer?.masksToBounds = true
        context.coordinator.driver.start()
        return canvas
    }

    func updateNSView(_ canvas: MilkDropCanvas, context: Context) {
        canvas.layer?.cornerRadius = cornerRadius
    }

    static func dismantleNSView(_ canvas: MilkDropCanvas, coordinator: Coordinator) {
        coordinator.driver.stop()
    }
}

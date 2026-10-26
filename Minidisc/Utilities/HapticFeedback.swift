import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Use light for navigation, medium for playback, heavy for destructive actions,
/// selection for pickers, and the notification variants for operation outcomes.
/// The Mac has no haptics, so there every case does nothing.
@MainActor
enum HapticFeedback {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error

    func trigger() {
        #if canImport(UIKit)
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}

import Intents
import SwiftUI

/// Whether this build carries `com.apple.developer.siri`. Without it, any INPreferences call
/// throws an Objective-C exception and terminates the app. The fork's free personal team cannot
/// use the entitlement (see FORK.md); set this to true when restoring it in Minidisc.entitlements.
/// App Intents, including the iOS 27 audio actions, do not need it.
nonisolated enum SiriKitEntitlement {
    static let isPresent = false
}

/// The SiriKit authorization row, shown only when the build has the Siri entitlement.
struct SiriSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var authorization = INPreferences.siriAuthorizationStatus()

    var body: some View {
        Section {
            Button(action: configure) {
                switch authorization {
                case .authorized:
                    Label("Manage Siri Access", systemImage: "gearshape")
                case .denied, .restricted:
                    Label("Open Settings", systemImage: "gearshape")
                default:
                    Label("Enable Siri", systemImage: "waveform")
                }
            }
            .accessibilityIdentifier("siri-authorization")
        } header: {
            Text("Siri")
        } footer: {
            Text("Allow Siri to search your Minidisc library and control music playback.")
            Text("You can revoke Siri access in iOS Settings.")
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        authorization = INPreferences.siriAuthorizationStatus()
    }

    private func configure() {
        if authorization != .notDetermined {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } else {
            INPreferences.requestSiriAuthorization { _ in
                Task { @MainActor in refresh() }
            }
        }
    }
}

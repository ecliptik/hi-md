#if canImport(UIKit)
import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Playback hub row naming where audio is going now, with the system output picker beside it.
/// Minidisc follows the system route; the picker is the same one the full player shows.
struct AudioOutputRow: View {
    @State private var outputName = AudioOutputRow.currentOutputName()

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Output")
                    .foregroundStyle(.primary)
                Group {
                    if outputName.isEmpty {
                        Text("Follows the system output.")
                    } else {
                        Text(verbatim: outputName)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            OutputPickerButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("Choose Audio Output")
        }
        .accessibilityElement(children: .contain)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            outputName = Self.currentOutputName()
        }
    }

    private static func currentOutputName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? ""
    }
}

private struct OutputPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(Color.minidiscAccent)
        view.tintColor = .secondaryLabel
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

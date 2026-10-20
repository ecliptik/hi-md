import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            HStack(spacing: 12) {
                WidgetArtwork(file: context.attributes.artworkFile).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    statusLine(context.state)
                    ProgressView(value: context.state.fraction).tint(.accentColor)
                }
                if !context.state.isFinished {
                    cancelButton(context.attributes.collectionID)
                }
            }
            .padding()
            .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetArtwork(file: context.attributes.artworkFile).frame(width: 40, height: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.isFinished { cancelButton(context.attributes.collectionID) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        statusLine(context.state)
                        ProgressView(value: context.state.fraction).tint(.accentColor)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isFinished ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(context.state.completed)/\(context.state.total)").font(.caption2.monospacedDigit())
            } minimal: {
                ProgressView(value: context.state.fraction).progressViewStyle(.circular).tint(.accentColor)
            }
        }
    }

    private func statusLine(_ state: DownloadActivityAttributes.ContentState) -> some View {
        Group {
            if state.isFinished {
                Text("Downloaded \(state.completed) of \(state.total) songs")
            } else if let current = state.currentTitle {
                Text("\(state.completed) of \(state.total) · \(current)")
            } else {
                Text("\(state.completed) of \(state.total) songs")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func cancelButton(_ id: String) -> some View {
        Button(intent: CancelMinidiscDownloadIntent(collectionID: id)) {
            Image(systemName: "xmark.circle.fill").font(.title2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("Cancel Download"))
    }
}

import SwiftUI

/// Settings > Storage > Auto-Caching: what Minidisc keeps on the phone by itself.
struct OfflineFavoritesSettingsSection: View {
    let settings: CacheSettings
    let sync: OfflineFavoritesSync

    var body: some View {
        Section {
            Toggle("Favorites", isOn: Binding(
                get: { settings.keepFavoritesOffline },
                set: { settings.keepFavoritesOffline = $0 }
            ))
            .accessibilityIdentifier("offline-favorites-toggle")
            Toggle("Recently Played", isOn: Binding(
                get: { settings.keepRecentlyPlayedOffline },
                set: { settings.keepRecentlyPlayedOffline = $0 }
            ))
            .accessibilityIdentifier("auto-cache-recent-toggle")
            Toggle("Pinned", isOn: Binding(
                get: { settings.keepPinnedOffline },
                set: { settings.keepPinnedOffline = $0 }
            ))
            .accessibilityIdentifier("auto-cache-pinned-toggle")
            Toggle("Upcoming Songs", isOn: Binding(
                get: { settings.cacheUpcomingSongs },
                set: { settings.cacheUpcomingSongs = $0 }
            ))
            .accessibilityIdentifier("auto-cache-upcoming-toggle")
            // Upcoming songs and the playing song use cellular data by their own rules
            // (Settings > Playback > Caching); this applies to the automatic copies above.
            Toggle("Use cellular data", isOn: Binding(
                get: { settings.cacheOverCellular },
                set: { settings.cacheOverCellular = $0 }
            ))
            .accessibilityIdentifier("auto-cache-cellular-toggle")

            LabeledContent("Disk usage") {
                usageText
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("offline-favorites-usage")

            if settings.keepsAnythingOffline {
                if sync.isSyncing {
                    HStack {
                        ProgressView()
                        if sync.total == 0 { Text("Preparing…").foregroundStyle(.secondary) }
                        else {
                            Text("\(sync.completed) of \(sync.total) tracks ready")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if sync.waitingForConnection {
                    Label("Waiting for a connection", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else if sync.waitingForWiFi {
                    Label("Waiting for an unrestricted connection", systemImage: "wifi")
                        .foregroundStyle(.secondary)
                }

                if let error = sync.error {
                    Text(error.displayMessage).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Sync Now") { sync.revision += 1 }
                    .disabled(sync.isSyncing || sync.waitingForConnection || sync.waitingForWiFi)
                    .accessibilityIdentifier("offline-favorites-sync")
            }
        } header: {
            Text("Auto-Caching")
        } footer: {
            Text("Favorites, the \(OfflineFavoritesSync.recentAlbumLimit) most recently played albums and pinned albums and playlists are saved automatically, outside Downloads and the stream cache limit; turning one off removes only its automatic copies. They use the stream cache format, and cellular data only when turned on here. Upcoming songs go into the stream cache; Caching sets how far ahead.")
        }
        .task { await sync.refreshUsage() }
    }

    private var usageText: Text {
        let size = ByteCountFormatter.string(fromByteCount: sync.usage.bytes, countStyle: .file)
        if sync.usage.count == 1 { return Text("1 track · \(size)") }
        return Text("\(sync.usage.count) tracks · \(size)")
    }
}

/// A small progress ring in Home's toolbar while auto-caching saves songs. It shows only while
/// there is something to download, and opens Settings, where Auto-Caching lives.
struct AutoCachingIndicator: View {
    let sync: OfflineFavoritesSync
    let action: () -> Void

    var isActive: Bool { sync.isSyncing && sync.total > 0 && sync.completed < sync.total }

    var body: some View {
        if isActive {
            let fraction = Double(sync.completed) / Double(sync.total)
            Button(action: action) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.35), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(fraction, 0.04))
                        .stroke(Color.minidiscAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 20, height: 20)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auto-Caching")
            .accessibilityValue(Text(fraction.formatted(.percent.precision(.fractionLength(0)))))
            .accessibilityHint("Opens Settings")
            .transition(.opacity)
        }
    }
}

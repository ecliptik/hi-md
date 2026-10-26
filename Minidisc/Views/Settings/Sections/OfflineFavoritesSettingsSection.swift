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
            NavigationLink {
                CachingSettingsView(settings: settings)
            } label: {
                Text("Caching")
            }
            .accessibilityIdentifier("auto-cache-caching-link")
            // Upcoming songs and the playing song use cellular data by their own rules (Caching);
            // this applies to the automatic copies above.
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

/// The small "Auto-Caching 13%" capsule shown above the mini player while the sync runs.
struct AutoCachingIndicator: View {
    let sync: OfflineFavoritesSync

    var body: some View {
        if sync.isSyncing, sync.total > 0, sync.completed < sync.total {
            let fraction = Double(sync.completed) / Double(sync.total)
            HStack(spacing: MinidiscSpacing.s) {
                ProgressView().controlSize(.small)
                Text("Auto-Caching")
                    .font(.footnote.weight(.semibold))
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.vertical, MinidiscSpacing.s)
            .glassEffect(.regular, in: Capsule())
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

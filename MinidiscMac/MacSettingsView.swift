import SwiftUI

/// The Settings window (⌘,). Each tab edits the same settings models as the iOS app.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("Server", systemImage: "server.rack") {
                MacServerSettings()
            }
            // The iOS Settings pages, so both apps offer the same quality, loudness, equalizer,
            // autoplay and caching choices.
            Tab("Playback", systemImage: "play.circle") {
                NavigationStack { PlaybackSettingsView() }
            }
            Tab("Equalizer", systemImage: "slider.vertical.3") {
                NavigationStack { EqualizerView() }
            }
            Tab("Downloads", systemImage: "arrow.down.circle") {
                MacDownloadSettings()
            }
            Tab("AI Recommendations", systemImage: "sparkles") {
                MacAIRecommendationSettings()
            }
            Tab("Appearance", systemImage: "paintpalette") {
                MacAppearanceSettings()
            }
        }
        .frame(width: 560)
        .tint(Color.minidiscAccent)
    }
}

private struct MacServerSettings: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        Form {
            if let container, !container.serverState.servers.isEmpty {
                Section {
                    Picker("Server", selection: activeServerBinding(container)) {
                        ForEach(container.serverState.servers, id: \.id) { server in
                            Text(server.displayName).tag(Optional(server.id))
                        }
                    }
                    if let server = container.serverState.activeServer {
                        LabeledContent("Connected as", value: server.username)
                        LabeledContent("Server URL", value: server.baseURL)
                        Button("Remove", role: .destructive) {
                            Task { try? await container.serverService.removeServer(id: server.id) }
                        }
                    }
                }
            }

            if let viewModel {
                Section("Add Server") {
                    @Bindable var viewModel = viewModel
                    TextField("Server URL", text: $viewModel.serverURL, prompt: Text(verbatim: "https://music.example.com"))
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                    if let error = viewModel.connectionError {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Connect & Save") {
                            Task { await connect(viewModel) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canSubmit || viewModel.isLoading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
        }
    }

    private func connect(_ viewModel: OnboardingViewModel) async {
        await viewModel.addServer()
        guard viewModel.connectionError == nil else { return }
        viewModel.serverURL = ""
        viewModel.username = ""
        viewModel.password = ""
    }

    private func activeServerBinding(_ container: AppContainer) -> Binding<UUID?> {
        Binding {
            container.serverState.activeServer?.id
        } set: { id in
            guard let id else { return }
            Task { try? await container.serverService.setActiveServer(id: id) }
        }
    }
}

// MARK: - Downloads

/// Offline mode, what is kept automatically, the stream cache and artwork.
private struct MacDownloadSettings: View {
    @Environment(\.appContainer) private var container
    @State private var cacheBytes: Int64 = 0
    @State private var showsClearCache = false

    var body: some View {
        Form {
            if let container {
                @Bindable var serverState = container.serverState
                let cache = container.cacheSettings
                Section {
                    Toggle("Offline Mode", isOn: $serverState.isOfflineModeEnabled)
                } footer: {
                    Text("Only show and play music saved on this device, even when connected to the internet.")
                }

                Section {
                    Toggle("Favorites", isOn: Binding(get: { cache.keepFavoritesOffline }, set: { cache.keepFavoritesOffline = $0 }))
                    Toggle("Recently Played", isOn: Binding(get: { cache.keepRecentlyPlayedOffline },
                                                            set: { cache.keepRecentlyPlayedOffline = $0 }))
                    Toggle("Pinned", isOn: Binding(get: { cache.keepPinnedOffline }, set: { cache.keepPinnedOffline = $0 }))
                    Toggle("Upcoming Songs", isOn: Binding(get: { cache.cacheUpcomingSongs }, set: { cache.cacheUpcomingSongs = $0 }))
                } header: {
                    Text("Auto-Caching")
                }

                Section {
                    LabeledContent("Used") {
                        Text(verbatim: "\(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: cache.capacityBytes, countStyle: .file))")
                            .monospacedDigit()
                    }
                    Stepper(value: Binding(get: { cache.capacityMegabytes }, set: { cache.capacityMegabytes = $0 }),
                            in: CacheSettings.minCapacityMegabytes...CacheSettings.maxCapacityMegabytes,
                            step: CacheSettings.capacityStepMegabytes) {
                        LabeledContent("Size") {
                            Text(ByteCountFormatter.string(fromByteCount: cache.capacityBytes, countStyle: .file))
                                .monospacedDigit()
                        }
                    }
                    Picker("Format", selection: Binding(get: { cache.cacheFormat }, set: { cache.cacheFormat = $0 })) {
                        ForEach(CacheFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Toggle("Save songs as they play", isOn: Binding(get: { cache.cacheWhilePlaying }, set: { cache.cacheWhilePlaying = $0 }))
                    HStack {
                        Spacer()
                        Button("Clear stream cache", role: .destructive) { showsClearCache = true }
                    }
                } header: {
                    Text("Stream cache")
                } footer: {
                    Text("Keeps recently-played music for instant replay. Least-recently-played tracks are removed when the size limit is reached.")
                }

                Section {
                    Toggle("Cache artwork", isOn: Binding(get: { cache.cacheArtwork }, set: { newValue in
                        cache.cacheArtwork = newValue
                        container.artworkImageCache.persistCoversEnabled = newValue
                    }))
                } header: {
                    Text("Artwork")
                } footer: {
                    Text("Covers re-download on demand. Turning caching off keeps artwork in memory only.")
                }
            }
        }
        .formStyle(.grouped)
        .task { cacheBytes = await container?.audioStreamCache.usedBytes ?? 0 }
        .confirmationDialog("Clear stream cache", isPresented: $showsClearCache) {
            Button("Clear stream cache", role: .destructive) {
                Task {
                    await container?.audioStreamCache.clearAll()
                    cacheBytes = await container?.audioStreamCache.usedBytes ?? 0
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Appearance

private struct MacAppearanceSettings: View {
    @AppStorage("minidisc.appTheme") private var theme: AppTheme = .system
    @AppStorage(MacInterface.showsMenuBarPlayerKey) private var showsMenuBarPlayer = true
    @Bindable private var appearance = AppearanceSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.label)).tag(option)
                    }
                }
                LabeledContent("Accent Color") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button {
                                appearance.accent = choice
                            } label: {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if appearance.accent == choice {
                                            Image(systemName: "checkmark")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(appearance.accent == choice ? choice.color : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(Text(choice.title))
                            .accessibilityLabel(Text(choice.title))
                            .accessibilityAddTraits(appearance.accent == choice ? .isSelected : [])
                        }
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your Mac's light or dark setting. The accent colour marks the playing song, buttons and selections.")
            }
            Section {
                Toggle("Show the mini player in the menu bar", isOn: $showsMenuBarPlayer)
            }
        }
        .formStyle(.grouped)
    }
}

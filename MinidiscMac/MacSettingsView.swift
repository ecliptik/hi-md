import SwiftUI

/// The Settings window (⌘,). Each tab edits the same settings models as the iOS app.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("Server", systemImage: "server.rack") {
                MacServerSettings()
            }
            Tab("Playback", systemImage: "play.circle") {
                MacPlaybackSettings()
            }
            Tab("Equalizer", systemImage: "slider.vertical.3") {
                MacEqualizerSettings()
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

// MARK: - Playback

/// Crossfade, gapless and ReplayGain, plus streaming quality and the lyrics source. Every change
/// tells the player, which applies it from the next transition without rebuilding the current one.
private struct MacPlaybackSettings: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        Form {
            if let container {
                crossfadeSection(container)
                replayGainSection(container)
                streamingSection(container)
                lyricsSection(container.lyricsSettings)
            }
        }
        .formStyle(.grouped)
    }

    private func crossfadeSection(_ container: AppContainer) -> some View {
        let settings = container.crossfadeSettings
        return Section {
            LabeledContent("Duration") {
                HStack {
                    Slider(value: Binding(get: { settings.duration }, set: { newValue in
                        settings.duration = newValue
                        Task { await container.playerService.crossfadeSettingsDidChange() }
                    }), in: CrossfadeSettings.minDuration...CrossfadeSettings.maxDuration, step: 0.5)
                    .frame(width: 200)
                    Text(settings.duration == 0 ? String(localized: "Off") : "\(String(format: "%.1f", settings.duration)) s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Toggle("Disable for gapless albums", isOn: Binding(get: { settings.disableForGapless }, set: { newValue in
                settings.disableForGapless = newValue
                Task { await container.playerService.crossfadeSettingsDidChange() }
            }))
            .disabled(settings.duration == 0)
        } header: {
            Text("Crossfade")
        } footer: {
            Text("Fades one track into the next over the set time. Set Off for no fade. The toggle keeps gapless albums and live mixes seamless.")
        }
    }

    private func replayGainSection(_ container: AppContainer) -> some View {
        let settings = container.replayGainSettings
        func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ReplayGainSettings, Value>) -> Binding<Value> {
            Binding(get: { settings[keyPath: keyPath] }, set: { newValue in
                settings[keyPath: keyPath] = newValue
                Task { await container.playerService.replayGainSettingsDidChange() }
            })
        }
        return Section {
            Toggle("ReplayGain", isOn: binding(\.enabled))
            Picker("Mode", selection: binding(\.mode)) {
                Text("Track").tag(ReplayGainMode.track)
                Text("Album").tag(ReplayGainMode.album)
            }
            .disabled(!settings.enabled)
            LabeledContent("Pre-amp") {
                HStack {
                    Slider(value: binding(\.preAmp), in: ReplayGainSettings.minPreAmp...ReplayGainSettings.maxPreAmp, step: 0.5)
                        .frame(width: 200)
                    Text(verbatim: "\(settings.preAmp > 0 ? "+" : "")\(String(format: "%.1f", settings.preAmp)) dB")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .disabled(!settings.enabled)
            Toggle("Prevent clipping", isOn: binding(\.preventClipping))
                .disabled(!settings.enabled)
        } header: {
            Text("ReplayGain")
        } footer: {
            Text("Evens out the volume between tracks. Track mode levels each song on its own, and Album mode keeps an album's dynamics.")
        }
    }

    private func streamingSection(_ container: AppContainer) -> some View {
        let stream = container.streamSettings
        return Section {
            Picker("Quality", selection: Binding(get: { stream.wifiQuality }, set: { stream.wifiQuality = $0 })) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
        } header: {
            Text("Streaming")
        } footer: {
            Text("The server transcodes to the chosen tier. Original streams your files untouched (lossless). Applies to the next track.")
        }
    }

    private func lyricsSection(_ settings: LyricsSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker("Lyrics source", selection: $settings.source) {
                ForEach(LyricsSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
        } header: {
            Text("Lyrics")
        } footer: {
            Text("Auto checks Navidrome first and falls back to LRCLIB. LRCLIB requests include the track title, artist, album, and duration.")
        }
    }
}

// MARK: - Equalizer

/// The 10-band equalizer, its presets and the preamp, shared with the iOS app's settings.
private struct MacEqualizerSettings: View {
    @Bindable private var settings = EqualizerSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Equalizer", isOn: $settings.isEnabled)
                Picker("Preset", selection: Binding(
                    get: { settings.preset },
                    set: { if let preset = $0 { settings.apply(preset) } }
                )) {
                    if settings.preset == nil {
                        Text("Custom").tag(EqualizerPreset?.none)
                    }
                    ForEach(EqualizerPreset.allCases) { preset in
                        Text(preset.title).tag(EqualizerPreset?.some(preset))
                    }
                }
            } footer: {
                Text("Applies to streamed and downloaded music, including crossfades.")
            }

            Section("Bands") {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<Equalizer.bandCount, id: \.self) { band in
                        MacEqualizerBand(
                            label: Self.frequencyLabel(Equalizer.frequencies[band]),
                            value: Binding(get: { settings.gains[band] }, set: { settings.setGain($0, band: band) })
                        )
                    }
                }
                .padding(.vertical, 8)
                .disabled(!settings.isEnabled)
                .opacity(settings.isEnabled ? 1 : 0.45)
            }

            Section {
                LabeledContent("Preamp") {
                    HStack {
                        Slider(value: Binding(get: { settings.preamp }, set: { settings.setPreamp($0) }),
                               in: Equalizer.gainRange.lowerBound...0, step: 0.5)
                            .frame(width: 200)
                            .accessibilityLabel("Preamp")
                        Text(Self.decibels(settings.preamp))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Reset to Flat") { settings.apply(.flat) }
                }
            } footer: {
                Text("Lower the preamp if boosted bands sound distorted.")
            }
            .disabled(!settings.isEnabled)
        }
        .formStyle(.grouped)
    }

    static func frequencyLabel(_ frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }

    static func decibels(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false))) + " dB"
    }
}

/// One band: its gain above a vertical slider, and the frequency below.
private struct MacEqualizerBand: View {
    let label: String
    @Binding var value: Float
    private let height: CGFloat = 150

    var body: some View {
        VStack(spacing: 6) {
            Text(value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: $value, in: Equalizer.gainRange, step: 0.5)
                .controlSize(.small)
                .frame(width: height)
                .rotationEffect(.degrees(-90))
                .frame(width: 26, height: height)
                .accessibilityLabel(Text("\(label)Hz"))
                .accessibilityValue(MacEqualizerSettings.decibels(value))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

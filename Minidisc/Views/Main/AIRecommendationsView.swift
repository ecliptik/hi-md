import OSLog
import SwiftUI

/// Albums suggested by the chosen AI provider, each marked as in the library or not.
struct AIRecommendationsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.openURL) private var openURL
    @State private var results: [AIRecommendationResult] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var lidarrTarget: LidarrTarget?

    private struct LidarrTarget: Identifiable {
        let artist: LidarrArtistLookup
        let client: LidarrClient
        var id: String { artist.id }
    }

    var body: some View {
        List {
            if let settings = container?.aiRecommendationSettings {
                Section {
                    Label {
                        Text("Suggested by \(Text(settings.provider.title))")
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(Color.minidiscAccent)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            if isLoading {
                HStack(spacing: MinidiscSpacing.s) {
                    ProgressView()
                    Text("Thinking about your library…").foregroundStyle(.secondary)
                }
            } else if let error {
                EmptyStateView(systemImage: "sparkles", title: "No recommendations", subtitle: LocalizedStringKey(error),
                               action: .init(label: "Try Again") { Task { await load() } })
                    .listRowSeparator(.hidden)
            }
            ForEach(results) { result in
                row(result)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recommended for You")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                    .disabled(isLoading)
            }
        }
        .task { if results.isEmpty { await load() } }
        .sheet(item: $lidarrTarget) { target in
            LidarrAddArtistSheet(artist: target.artist, client: target.client) { lidarrTarget = nil }
        }
        .miniPlayerBottomMargin()
    }

    @ViewBuilder
    private func row(_ result: AIRecommendationResult) -> some View {
        let item = result.recommendation
        VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.album).font(.headline)
                    Text(item.year.map { "\(item.artist) · \(String($0))" } ?? item.artist)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if case .inLibrary = result.availability {
                    Label("In Library", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.minidiscAccent)
                }
            }
            Text(item.reason).font(.footnote).foregroundStyle(.secondary)
            actions(result)
                .padding(.top, MinidiscSpacing.xs)
        }
        .padding(.vertical, MinidiscSpacing.xs)
    }

    @ViewBuilder
    private func actions(_ result: AIRecommendationResult) -> some View {
        let item = result.recommendation
        HStack(spacing: MinidiscSpacing.s) {
            switch result.availability {
            case .inLibrary(let albumID, let cover):
                NavigationLink(value: HomeDestination.albumById(id: albumID, name: item.album, subtitle: item.artist, coverArtId: cover)) {
                    Text("Open Album")
                }
                .buttonStyle(.bordered)
            case .artistInLibrary, .missing:
                if container?.lidarrSettings.isConnected == true {
                    Button("Add to Lidarr", systemImage: "plus") { Task { await addToLidarr(item) } }
                        .buttonStyle(.borderedProminent)
                }
                Button("Bandcamp") { if let url = AIRecommendationLinks.bandcamp(item) { openURL(url) } }
                    .buttonStyle(.bordered)
                Button("MusicBrainz") { if let url = AIRecommendationLinks.musicBrainz(item) { openURL(url) } }
                    .buttonStyle(.bordered)
            }
        }
        .font(.footnote)
        .tint(.minidiscAccent)
    }

    private func load() async {
        guard let container else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            results = try await AIRecommender(container: container, settings: container.aiRecommendationSettings).recommend()
        } catch let failure as AIRecommendationError {
            error = String(localized: failure.localizedStringResource)
        } catch let failure as MusicIntentError {
            error = String(localized: failure.localizedStringResource)
        } catch is CancellationError {
        } catch {
            Logger.ui.error("AI recommendations failed: \(error, privacy: .public)")
            self.error = String(localized: "Couldn't reach the recommendation service. Check your connection.")
        }
    }

    /// Finds the artist in Lidarr's lookup and opens the usual Add Artist sheet.
    private func addToLidarr(_ item: AIRecommendation) async {
        guard let client = await container?.lidarrSettings.makeClient() else { return }
        do {
            let matches = try await client.searchArtists(term: item.artist)
            let key = AIRecommendationMatcher.key(item.artist)
            guard let artist = matches.first(where: { AIRecommendationMatcher.key($0.artistName) == key }) ?? matches.first else {
                container?.toastService.showError(String(localized: "Lidarr couldn't find \(item.artist)."))
                return
            }
            if artist.isAlreadyAdded {
                container?.toastService.show(String(localized: "\(item.artist) is already in Lidarr."), style: .info, duration: 3)
                return
            }
            lidarrTarget = LidarrTarget(artist: artist, client: client)
        } catch {
            container?.toastService.showError(String(localized: "Couldn't reach Lidarr."))
        }
    }
}

/// Settings > Integrations > AI Recommendations.
struct AIRecommendationSettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var saved = false

    var body: some View {
        if let settings = container?.aiRecommendationSettings {
            form(settings)
        }
    }

    private func form(_ settings: AIRecommendationSettings) -> some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(AIRecommendationProvider.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Apple Intelligence runs on this device. Anthropic and OpenAI receive the names of your recently played and favourite albums, most collected artists and playlists, and use your own API key.")
            }
            if settings.provider == .anthropic {
                Section("Anthropic") {
                    SecureField("API Key", text: $anthropicKey)
                    TextField("Model", text: $settings.anthropicModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            if settings.provider == .openAI {
                Section("OpenAI") {
                    SecureField("API Key", text: $openAIKey)
                    TextField("Model", text: $settings.openAIModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            if settings.provider.needsAPIKey {
                Section {
                    Button(saved ? "Saved" : "Save Key") {
                        Task {
                            try? await settings.setAPIKey(anthropicKey, for: .anthropic)
                            try? await settings.setAPIKey(openAIKey, for: .openAI)
                            saved = true
                        }
                    }
                } footer: {
                    Text("Keys are stored in the keychain on this device.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Recommendations")
        .navigationBarTitleDisplayModeInline()
        .task {
            anthropicKey = await settings.apiKey(for: .anthropic) ?? ""
            openAIKey = await settings.apiKey(for: .openAI) ?? ""
        }
        .onChange(of: anthropicKey) { saved = false }
        .onChange(of: openAIKey) { saved = false }
    }
}

/// The Discover entry point for AI recommendations.
struct AIRecommendationsCard: View {
    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.minidiscAccent)
                .frame(width: 44, height: 44)
                .background(Color.minidiscAccent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Recommended for You").font(.headline)
                Text("Albums picked from your listening").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(MinidiscSpacing.l)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

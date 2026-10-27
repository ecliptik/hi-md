import OSLog
import SwiftUI

/// Albums suggested by the chosen AI provider, each marked as in the library or not.
struct AIRecommendationsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.openURL) private var openURL
    @State private var results: [AIRecommendationResult] = []
    /// Who suggested `results`, for the shared list's heading.
    @State private var resultsProvider: AIRecommendationProvider?
    @State private var isLoading = false
    @State private var failure: Failure?
    @State private var lidarrTarget: LidarrTarget?
    @State private var showSettings = false

    private struct LidarrTarget: Identifiable {
        let artist: LidarrArtistLookup
        let client: LidarrClient
        var id: String { artist.id }
    }

    private struct Failure: Equatable {
        let message: String
        var detail: String?
        var isFixedInSettings = false
    }

    var body: some View {
        List {
            if let settings = container?.aiRecommendationSettings {
                Section {
                    Label {
                        Text("Suggested by \(settings.provider.assistantName)")
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(Color.minidiscAccent)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if settings.needsSharingNotice(for: settings.provider) {
                    sharingNotice(settings)
                }
            }
            if isLoading {
                HStack(spacing: MinidiscSpacing.s) {
                    ProgressView()
                    Text("Thinking about your library…").foregroundStyle(.secondary)
                }
            } else if let failure {
                VStack(spacing: MinidiscSpacing.s) {
                    EmptyStateView(
                        systemImage: "sparkles", title: "No recommendations", subtitle: LocalizedStringKey(failure.message),
                        action: failure.isFixedInSettings
                            ? .init(label: "Open Settings") { showSettings = true }
                            : .init(label: "Try Again") { Task { await load() } }
                    )
                    if let detail = failure.detail {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
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
                ShareLink(item: shareAllText, subject: Text("Recommended for You")) {
                    Label("Share All", systemImage: "square.and.arrow.up")
                }
                .disabled(results.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                    .disabled(isLoading || needsSharingNotice)
            }
        }
        .task { if results.isEmpty, !needsSharingNotice { await load() } }
        .sheet(isPresented: $showSettings, onDismiss: { if !needsSharingNotice { Task { await load() } } }) {
            NavigationStack {
                AIRecommendationSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(item: $lidarrTarget) { target in
            LidarrAddArtistSheet(artist: target.artist, client: target.client) { lidarrTarget = nil }
        }
        .miniPlayerBottomMargin()
    }

    private var needsSharingNotice: Bool {
        guard let settings = container?.aiRecommendationSettings else { return false }
        return settings.needsSharingNotice(for: settings.provider)
    }

    private var shareAllText: String {
        let provider = resultsProvider ?? container?.aiRecommendationSettings.provider ?? .appleIntelligence
        return AIRecommendationShareText.all(
            results.map(\.recommendation), heading: String(localized: "Album suggestions from \(provider.assistantName)")
        )
    }

    /// Shown once per cloud provider, before anything is sent to it.
    private func sharingNotice(_ settings: AIRecommendationSettings) -> some View {
        let provider = settings.provider
        return Section {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                Label("What Hi-MD sends to \(provider.title)", systemImage: "hand.raised")
                    .font(.headline)
                Text("To suggest albums, Hi-MD sends \(provider.title) the names of up to 20 recently played albums, 15 favourite albums, your 25 most collected artists and 15 playlists. Nothing else is sent: no server address, account details or play counts. The terms of your API key apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, MinidiscSpacing.xs)
            Button("Continue") {
                settings.acknowledgeSharing(for: provider)
                Task { await load() }
            }
            Button("Use Apple Intelligence Instead") {
                settings.provider = .appleIntelligence
                Task { await load() }
            }
        }
        .tint(.minidiscTextAccent)
    }

    @ViewBuilder
    private func row(_ result: AIRecommendationResult) -> some View {
        let item = result.recommendation
        let shareText = AIRecommendationShareText.single(item)
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
                ShareLink(item: shareText, subject: Text(item.album)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Text(item.reason).font(.footnote).foregroundStyle(.secondary)
            actions(result)
                .padding(.top, MinidiscSpacing.xs)
        }
        .padding(.vertical, MinidiscSpacing.xs)
        .contextMenu {
            ShareLink(item: shareText, subject: Text(item.album)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button("Copy", systemImage: "doc.on.doc") { PlatformPasteboard.copy(shareText) }
        }
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
                        // A fill behind white text, so the fill shade rather than the text one.
                        .tint(.minidiscAccent)
                }
                Button("Bandcamp") { if let url = AIRecommendationLinks.bandcamp(item) { openURL(url) } }
                    .buttonStyle(.bordered)
                Button("MusicBrainz") { if let url = AIRecommendationLinks.musicBrainz(item) { openURL(url) } }
                    .buttonStyle(.bordered)
            }
        }
        .font(.footnote)
        .tint(.minidiscTextAccent)
    }

    private func load() async {
        guard let container else { return }
        let settings = container.aiRecommendationSettings
        if resultsProvider != settings.provider { results = [] }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            results = try await AIRecommender(container: container, settings: settings).recommend()
            resultsProvider = settings.provider
        } catch let error as AIRecommendationError {
            failure = Failure(message: String(localized: error.localizedStringResource), detail: error.detail,
                              isFixedInSettings: error.isFixedInSettings)
        } catch let error as MusicIntentError {
            failure = Failure(message: String(localized: error.localizedStringResource))
        } catch is CancellationError {
        } catch {
            Logger.ui.error("AI recommendations failed: \(error, privacy: .public)")
            failure = Failure(message: String(localized: "Couldn't reach the recommendation service. Check your connection."))
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
    /// Re-masks a revealed key when the app leaves the foreground.
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyDraft = ""
    /// The key as last loaded or saved, and whose it is. Nil while switching providers.
    @State private var storedKey: StoredKey?
    @State private var showKey = false
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private struct StoredKey: Equatable {
        let provider: AIRecommendationProvider
        var value: String
    }

    private enum TestResult: Equatable {
        case success
        case failure(String)
    }

    var body: some View {
        if let settings = container?.aiRecommendationSettings {
            form(settings)
        }
    }

    private func form(_ settings: AIRecommendationSettings) -> some View {
        @Bindable var settings = settings
        let provider = settings.provider
        let hasKey = !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Form {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(AIRecommendationProvider.allCases) { Text($0.title).tag($0) }
                }
                if provider == .appleIntelligence, !AIRecommender.isAppleIntelligenceAvailable {
                    warning("Apple Intelligence isn't available on this device right now.")
                }
            } footer: {
                Text("Apple Intelligence runs on this device. Anthropic and OpenAI receive the names of your recently played and favourite albums, most collected artists and playlists, and use your own API key.")
            }
            if provider.needsAPIKey {
                Section {
                    if !hasKey, storedKey != nil {
                        warning("Enter your \(provider.title) API key to get recommendations.")
                    }
                    keyField
                    LabeledContent("Model") {
                        TextField("Model", text: provider == .anthropic ? $settings.anthropicModel : $settings.openAIModel,
                                  prompt: Text(verbatim: provider.defaultModel ?? ""))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                            .multilineTextAlignment(.trailing)
                    }
                    Button {
                        Task { await testConnection(settings) }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(!hasKey || isTesting)
                    if let testResult {
                        switch testResult {
                        case .success:
                            Label("Connected.", systemImage: "checkmark.circle")
                                .font(.minidiscCaption)
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.minidiscCaption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text(verbatim: provider.title)
                } footer: {
                    VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                        Text("Leave Model empty to use \(provider.defaultModel ?? ""), or enter any model your key can use.")
                        if provider == .anthropic {
                            Text("claude-sonnet-5-5 and claude-haiku-5-5 answer faster and cost less.")
                        }
                        Text("Keys are stored in the keychain on this device.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Recommendations")
        .navigationBarTitleDisplayModeInline()
        .task(id: provider) {
            storedKey = nil
            testResult = nil
            let key = await settings.apiKey(for: provider) ?? ""
            keyDraft = key
            storedKey = StoredKey(provider: provider, value: key)
        }
        .onChange(of: keyDraft) { _, draft in
            // Only the user's edits are saved, never the draft loaded for another provider.
            guard let storedKey, storedKey.provider == settings.provider, storedKey.value != draft else { return }
            settings.saveAPIKey(draft, for: storedKey.provider)
            self.storedKey?.value = draft
            testResult = nil
        }
        .onChange(of: settings.model(for: provider)) { testResult = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { showKey = false }
        }
    }

    /// Masked by default, with an eye button to check what was pasted.
    private var keyField: some View {
        HStack {
            Group {
                if showKey {
                    TextField("API Key", text: $keyDraft)
                } else {
                    SecureField("API Key", text: $keyDraft)
                }
            }
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            Button(showKey ? "Hide Key" : "Show Key", systemImage: showKey ? "eye.slash" : "eye") { showKey.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.orange)
    }

    /// One tiny request with the typed key and model. No listening data is sent.
    private func testConnection(_ settings: AIRecommendationSettings) async {
        let provider = settings.provider
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        let result: TestResult
        do {
            try await AIRecommendationCloudClient().testConnection(provider: provider, key: key, model: settings.model(for: provider))
            result = .success
        } catch let error as AIRecommendationError {
            let message = String(localized: error.localizedStringResource)
            result = .failure(error.detail.map { message + "\n" + $0 } ?? message)
        } catch is CancellationError {
            return
        } catch {
            result = .failure(String(localized: "Couldn't reach the recommendation service. Check your connection."))
        }
        if settings.provider == provider { testResult = result }
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

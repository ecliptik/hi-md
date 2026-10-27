import OSLog
import SwiftUI

/// Recommended for You: albums suggested by the chosen AI provider from the user's listening, each
/// marked as in the library or not. A port of the iOS screen, with ShareLink sharing. Opened from
/// Discover.
struct MacRecommendationsView: View {
    let container: AppContainer

    @Environment(\.openURL) private var openURL
    @State private var results: [AIRecommendationResult] = []
    /// Who suggested `results`, for the shared list's heading.
    @State private var resultsProvider: AIRecommendationProvider?
    @State private var isLoading = false
    @State private var failure: Failure?

    private struct Failure: Equatable {
        let message: String
        var detail: String?
        var isFixedInSettings = false
    }

    private var settings: AIRecommendationSettings { container.aiRecommendationSettings }
    private var needsSharingNotice: Bool { settings.needsSharingNotice(for: settings.provider) }

    var body: some View {
        List {
            Section {
                Label {
                    Text("Suggested by \(settings.provider.assistantName)")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Color.minidiscAccent)
                }
                .foregroundStyle(.secondary)
            }
            if needsSharingNotice {
                sharingNotice
            }
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking about your library…").foregroundStyle(.secondary)
                }
            } else if let failure {
                failureView(failure)
            }
            ForEach(results) { result in
                row(result)
            }
        }
        .listStyle(.inset)
        .navigationTitle("Recommended for You")
        .toolbar {
            ToolbarItemGroup {
                ShareLink(item: shareAllText, subject: Text("Recommended for You")) {
                    Label("Share All", systemImage: "square.and.arrow.up")
                }
                .disabled(results.isEmpty)
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                    .disabled(isLoading || needsSharingNotice)
            }
        }
        .task { if results.isEmpty, !needsSharingNotice { await load() } }
    }

    private var shareAllText: String {
        let provider = resultsProvider ?? settings.provider
        return AIRecommendationShareText.all(
            results.map(\.recommendation), heading: String(localized: "Album suggestions from \(provider.assistantName)")
        )
    }

    /// Shown once per cloud provider, before anything is sent to it.
    private var sharingNotice: some View {
        let provider = settings.provider
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("What Hi-MD sends to \(provider.title)", systemImage: "hand.raised")
                    .font(.headline)
                Text("To suggest albums, Hi-MD sends \(provider.title) the names of up to 20 recently played albums, 15 favourite albums, your 25 most collected artists and 15 playlists. Nothing else is sent: no server address, account details or play counts. The terms of your API key apply.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Continue") {
                        settings.acknowledgeSharing(for: provider)
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Use Apple Intelligence Instead") {
                        settings.provider = .appleIntelligence
                        Task { await load() }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
        }
    }

    private func failureView(_ failure: Failure) -> some View {
        VStack(spacing: 8) {
            ContentUnavailableView {
                Label("No recommendations", systemImage: "sparkles")
            } description: {
                Text(LocalizedStringKey(failure.message))
            } actions: {
                if failure.isFixedInSettings {
                    SettingsLink { Text("Open Settings") }
                } else {
                    Button("Try Again") { Task { await load() } }
                }
            }
            if let detail = failure.detail {
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ result: AIRecommendationResult) -> some View {
        let item = result.recommendation
        let shareText = AIRecommendationShareText.single(item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.album).font(.headline)
                    Text(item.year.map { "\(item.artist) · \(String($0))" } ?? item.artist)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .inLibrary = result.availability {
                    Label("In Library", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.minidiscAccent)
                        .help("In Library")
                }
                ShareLink(item: shareText, subject: Text(item.album)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
            Text(item.reason)
                .foregroundStyle(.secondary)
            actions(result)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
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
        HStack(spacing: 8) {
            switch result.availability {
            case .inLibrary(let albumID, _):
                NavigationLink(value: MacDestination.album(id: albumID)) {
                    Text("Open Album")
                }
                .buttonStyle(.bordered)
            case .artistInLibrary, .missing:
                Button("Bandcamp") { if let url = AIRecommendationLinks.bandcamp(item) { openURL(url) } }
                    .buttonStyle(.bordered)
                Button("MusicBrainz") { if let url = AIRecommendationLinks.musicBrainz(item) { openURL(url) } }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
    }

    private func load() async {
        let settings = settings
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
}

/// Settings > AI Recommendations: the provider, and for Anthropic and OpenAI the API key, kept in
/// the keychain, and the model.
struct MacAIRecommendationSettings: View {
    @Environment(\.appContainer) private var container
    @Environment(\.controlActiveState) private var controlActiveState
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
                    TextField("Model", text: provider == .anthropic ? $settings.anthropicModel : $settings.openAIModel,
                              prompt: Text(verbatim: provider.defaultModel ?? ""))
                        .autocorrectionDisabled()
                    HStack {
                        if let testResult {
                            switch testResult {
                            case .success:
                                Label("Connected.", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                            case .failure(let message):
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if isTesting {
                            ProgressView().controlSize(.small)
                        }
                        Button("Test Connection") { Task { await testConnection(settings) } }
                            .disabled(!hasKey || isTesting)
                    }
                } header: {
                    Text(verbatim: provider.title)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
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
        .onChange(of: controlActiveState) { _, state in
            // Mask a revealed key when the Settings window loses focus.
            if state == .inactive { showKey = false }
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
            Button(showKey ? "Hide Key" : "Show Key", systemImage: showKey ? "eye.slash" : "eye") { showKey.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
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

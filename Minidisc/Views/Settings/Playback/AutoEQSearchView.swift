import SwiftUI

/// Settings > Playback > Equalizer > Search Presets: finds a headphone in AutoEQ and applies its
/// correction to the equalizer.
struct AutoEQSearchView: View {
    let settings: EqualizerSettings
    var client: AutoEQClient = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [AutoEQEntry] = []
    @State private var phase = Phase.loading
    @State private var applying: AutoEQEntry.ID?
    @State private var applyError: AutoEQError?

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(AutoEQError)
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .navigationTitle("Search Presets")
        .navigationBarTitleDisplayModeInline()
        .searchable(text: $query, prompt: Text("Headphone name"))
        .autocorrectionDisabled()
        .task { await loadIndex() }
        .task(id: query) {
            guard phase == .ready else { return }
            // Debounce typing; a newer query cancels this task.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await search()
        }
        .alert("Couldn't Apply the Preset", isPresented: Binding(
            get: { applyError != nil },
            set: { if !$0 { applyError = nil } }
        )) {
            Button("OK", role: .cancel) { applyError = nil }
        } message: {
            Text(Self.message(for: applyError ?? .unreadable))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: MinidiscSpacing.m) {
                ProgressView()
                Text("Loading the AutoEQ index…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let error):
            Section {
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    Text(error == .offline ? "Can't Reach AutoEQ" : "AutoEQ Is Unavailable")
                        .font(.headline)
                    Text(Self.message(for: error))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, MinidiscSpacing.xs)
                Button("Try Again") { Task { await loadIndex() } }
            }
        case .ready:
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    Text("Type your headphones' name to apply AutoEQ's correction for them.")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Profiles come from the AutoEQ project, measured by the sources shown with each result.")
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Section {
                    ForEach(results) { entry in
                        resultRow(entry)
                    }
                }
            }
        }
    }

    private func resultRow(_ entry: AutoEQEntry) -> some View {
        Button {
            Task { await apply(entry) }
        } label: {
            HStack(spacing: MinidiscSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.name)
                        .foregroundStyle(.primary)
                    if !entry.source.isEmpty {
                        Text(verbatim: entry.source)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: MinidiscSpacing.s)
                if applying == entry.id {
                    ProgressView()
                } else if settings.profileName == entry.name {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MinidiscColors.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(applying != nil)
        .accessibilityAddTraits(settings.profileName == entry.name ? .isSelected : [])
    }

    private func loadIndex() async {
        phase = .loading
        do {
            _ = try await client.index()
            phase = .ready
            await search()
        } catch {
            phase = .failed(error as? AutoEQError ?? .offline)
        }
    }

    private func search() async {
        let text = query
        let found = (try? await client.search(text)) ?? []
        guard text == query else { return }
        results = found
    }

    private func apply(_ entry: AutoEQEntry) async {
        applying = entry.id
        defer { applying = nil }
        do {
            let mapped = try await client.profile(for: entry).bandGains()
            settings.apply(gains: mapped.gains, preamp: mapped.preamp, profileName: entry.name)
            settings.isEnabled = true
            HapticFeedback.light.trigger()
            dismiss()
        } catch {
            applyError = error as? AutoEQError ?? .offline
        }
    }

    private static func message(for error: AutoEQError) -> LocalizedStringKey {
        switch error {
        case .offline: "Check your internet connection and try again."
        case .notFound: "AutoEQ has no profile for these headphones that Hi-MD can read."
        case .tooLarge, .unreadable: "AutoEQ sent something Hi-MD couldn't read. Try again later."
        }
    }
}

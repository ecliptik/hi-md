import SwiftUI

/// Discover > Make a Playlist: describe a playlist, or tap an idea, and the AI makes it from the
/// library. The result can be renamed and trimmed before it's saved to the server.
struct AIPlaylistMakerView: View {
    @Environment(\.appContainer) private var container
    @State private var model: AIPlaylistMakerModel?
    @FocusState private var requestFocused: Bool

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Make a Playlist")
        .toolbarTitleDisplayMode(.inline)
        .task {
            guard model == nil, let container else { return }
            model = AIPlaylistMakerModel(container: container)
        }
    }

    @ViewBuilder
    private func content(_ model: AIPlaylistMakerModel) -> some View {
        @Bindable var model = model
        List {
            Section {
                Label {
                    Text("Made by \(model.provider.assistantName) from songs in your library")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Color.minidiscAccent)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if model.needsSharingNotice {
                sharingNotice(model)
            } else {
                requestSection(model)
                switch model.phase {
                case .idle:
                    ideasSection(model)
                case .making:
                    Section {
                        HStack(spacing: MinidiscSpacing.m) {
                            ProgressView()
                            Text("Choosing songs…").foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message, let fixInSettings):
                    Section {
                        Text(message).foregroundStyle(.secondary)
                        if fixInSettings {
                            NavigationLink("AI Recommendations Settings") { AIRecommendationSettingsView() }
                        }
                    }
                    ideasSection(model)
                case .ready, .saving, .saved:
                    draftSections(model)
                }
            }
        }
        .tint(.minidiscTextAccent)
        .task(id: model.needsSharingNotice) { await model.loadIdeas() }
        .onDisappear { model.cancel() }
    }

    private func requestSection(_ model: AIPlaylistMakerModel) -> some View {
        @Bindable var model = model
        return Section {
            TextField("Rainy Sunday trip-hop, 90s singalongs…", text: $model.request, axis: .vertical)
                .lineLimit(1...4)
                .focused($requestFocused)
                .submitLabel(.go)
                .onSubmit { model.make() }
            Button {
                requestFocused = false
                model.make()
            } label: {
                Label(model.hasDraft ? LocalizedStringKey("Make Another") : LocalizedStringKey("Make Playlist"), systemImage: "wand.and.sparkles")
            }
            .disabled(!model.canMake)
        } footer: {
            Text("Describe a feeling, an occasion, an era or a sound.")
        }
    }

    @ViewBuilder
    private func ideasSection(_ model: AIPlaylistMakerModel) -> some View {
        if model.isLoadingIdeas || !model.ideas.isEmpty {
            Section("Ideas for You") {
                if model.isLoadingIdeas && model.ideas.isEmpty {
                    HStack(spacing: MinidiscSpacing.m) {
                        ProgressView()
                        Text("Thinking of ideas…").foregroundStyle(.secondary)
                    }
                }
                ForEach(model.ideas) { idea in
                    Button {
                        requestFocused = false
                        model.use(idea)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.title).font(.headline).foregroundStyle(.primary)
                            Text(idea.prompt).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func draftSections(_ model: AIPlaylistMakerModel) -> some View {
        @Bindable var model = model
        Section {
            TextField("Playlist Name", text: $model.title)
                .font(.headline)
            if !model.summary.isEmpty {
                Text(model.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            switch model.phase {
            case .saved:
                Label("Saved to Playlists", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.minidiscTextAccent)
            default:
                Button {
                    Task { await model.save() }
                } label: {
                    if model.phase == .saving {
                        HStack(spacing: MinidiscSpacing.s) { ProgressView(); Text("Saving…") }
                    } else {
                        Label("Save to Playlists", systemImage: "plus.circle")
                    }
                }
                .disabled(model.phase == .saving || model.songs.isEmpty
                          || model.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        Section {
            ForEach(Array(model.displaySongs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, index: index + 1, showCoverArt: true, trailingAccessory: .duration, onTap: {
                    let songs = model.displaySongs
                    Task {
                        await container?.toastService.perform {
                            try await container?.playerService.play(tracks: songs, startIndex: index)
                        }
                    }
                })
            }
            .onDelete { model.remove(at: $0) }
            .deleteDisabled(model.phase != .ready)
        } header: {
            Text("\(model.songs.count) songs")
        } footer: {
            if model.phase == .ready { Text("Swipe a song to leave it out before saving.") }
        }
    }

    /// Shown once per cloud provider, before song names are sent to it.
    private func sharingNotice(_ model: AIPlaylistMakerModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                Label("What Hi-MD sends to \(model.provider.title)", systemImage: "hand.raised")
                    .font(.headline)
                Text(AIPlaylistSharingNotice.text(for: model.provider))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, MinidiscSpacing.xs)
            Button("Continue") { model.acknowledgeSharing() }
            Button("Use Apple Intelligence Instead") { model.useAppleIntelligence() }
        }
    }
}

/// The Discover entry point for Make a Playlist.
struct AIPlaylistMakerCard: View {
    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Image(systemName: "wand.and.sparkles")
                .font(.title2)
                .foregroundStyle(Color.minidiscAccent)
                .frame(width: 44, height: 44)
                .background(Color.minidiscAccent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Make a Playlist").font(.headline)
                Text("Describe it, and AI picks from your library").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(MinidiscSpacing.l)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

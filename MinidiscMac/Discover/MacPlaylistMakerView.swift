import SwiftUI

/// Discover > Make a Playlist on the Mac: describe a playlist or click an idea, and the AI chosen
/// in Settings makes it from the library. The songs can be reordered, removed with Delete, and
/// the playlist renamed before it's saved to the server.
struct MacPlaylistMakerView: View {
    let container: AppContainer

    @State private var model: AIPlaylistMakerModel?
    @FocusState private var requestFocused: Bool

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Make a Playlist")
        .task {
            if model == nil { model = AIPlaylistMakerModel(container: container) }
            requestFocused = true
        }
        .onDisappear { model?.cancel() }
    }

    private func content(_ model: AIPlaylistMakerModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Made by \(model.provider.assistantName) from songs in your library")
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Color.minidiscAccent)
            }
            .foregroundStyle(.secondary)

            if model.needsSharingNotice {
                sharingNotice(model)
                Spacer()
            } else {
                requestField(model)
                switch model.phase {
                case .idle:
                    ideas(model)
                    Spacer()
                case .making:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Choosing songs…").foregroundStyle(.secondary)
                    }
                    Spacer()
                case .failed(let message, let fixInSettings):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.secondary)
                        if fixInSettings { SettingsLink { Text("Open Settings") } }
                    }
                    ideas(model)
                    Spacer()
                case .ready, .saving, .saved:
                    draft(model)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: model.needsSharingNotice) { await model.loadIdeas() }
    }

    private func requestField(_ model: AIPlaylistMakerModel) -> some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            TextField("Rainy Sunday trip-hop, 90s singalongs…", text: $model.request)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($requestFocused)
                .onSubmit { model.make() }
            Button {
                model.make()
            } label: {
                Label(model.hasDraft ? LocalizedStringKey("Make Another") : LocalizedStringKey("Make Playlist"), systemImage: "wand.and.sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canMake)
        }
    }

    @ViewBuilder
    private func ideas(_ model: AIPlaylistMakerModel) -> some View {
        if model.isLoadingIdeas && model.ideas.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Thinking of ideas…").foregroundStyle(.secondary)
            }
        } else if !model.ideas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ideas for You").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(model.ideas) { idea in
                        MacPlaylistIdeaButton(idea: idea) { model.use(idea) }
                    }
                }
            }
        }
    }

    private func draft(_ model: AIPlaylistMakerModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Playlist Name", text: $model.title)
                    .textFieldStyle(.plain)
                    .font(.title.bold())
                switch model.phase {
                case .saved:
                    Label("Saved to Playlists", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.minidiscTextAccent)
                case .saving:
                    ProgressView().controlSize(.small)
                default:
                    Button("Save to Playlists", systemImage: "plus.circle") { Task { await model.save() } }
                        .disabled(model.songs.isEmpty || model.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text(model.summary.isEmpty ? String(localized: "\(model.songs.count) songs")
                                       : String(localized: "\(model.summary) · \(model.songs.count) songs"))
                .foregroundStyle(.secondary)
            MacSongTable(songs: model.displaySongs, style: .playlist, editing: model.phase == .ready ? editing(model) : nil)
        }
    }

    /// The draft isn't on the server yet, so the table's playlist edits change it here.
    private func editing(_ model: AIPlaylistMakerModel) -> MacSongTable.PlaylistEditing {
        MacSongTable.PlaylistEditing(
            playlistID: "ai-playlist-draft",
            remove: { model.remove(at: $0) },
            move: { model.move(from: $0, to: $1) },
            add: { _ in }
        )
    }

    /// Shown once per cloud provider, before song names are sent to it.
    private func sharingNotice(_ model: AIPlaylistMakerModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What Hi-MD sends to \(model.provider.title)", systemImage: "hand.raised")
                .font(.headline)
            Text(AIPlaylistSharingNotice.text(for: model.provider))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Continue") { model.acknowledgeSharing() }
                    .buttonStyle(.borderedProminent)
                Button("Use Apple Intelligence Instead") { model.useAppleIntelligence() }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

private struct MacPlaylistIdeaButton: View {
    let idea: AIPlaylistIdea
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title).font(.headline)
                Text(idea.prompt).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The Discover entry point for Make a Playlist.
struct MacPlaylistMakerCard: View {
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: MacDestination.playlistMaker) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.minidiscAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.minidiscAccent.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make a Playlist")
                        .font(.headline)
                    Text("Describe it, and AI picks from your library")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

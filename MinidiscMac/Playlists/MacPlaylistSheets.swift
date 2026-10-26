import SwiftData
import SwiftSonic
import SwiftUI

extension View {
    /// Presents the playlist requests started from menus anywhere in the window: naming a new
    /// playlist, renaming, confirming a delete, and songs that are already in a playlist.
    func macPlaylistSheets(_ playlists: MacPlaylists, navigator: MacNavigator) -> some View {
        modifier(MacPlaylistSheets(playlists: playlists, navigator: navigator))
    }
}

private struct MacPlaylistSheets: ViewModifier {
    @Bindable var playlists: MacPlaylists
    let navigator: MacNavigator

    @Query private var downloadedPlaylists: [DownloadedPlaylist]

    func body(content: Content) -> some View {
        let deleting = playlists.deleting
        content
            .sheet(item: $playlists.creation) { creation in
                MacPlaylistNameSheet(title: "New Playlist", confirmTitle: "Create",
                                     message: creation.songs.isEmpty ? nil : "\(creation.songs.count) songs selected") { name in
                    guard let playlist = await playlists.library.create(name: name, songs: creation.songs) else { return false }
                    navigator.selection = .playlist(id: playlist.id)
                    return true
                }
            }
            .sheet(item: $playlists.renaming) { playlist in
                MacPlaylistNameSheet(title: "Rename Playlist", confirmTitle: "Rename", initialName: playlist.name) { name in
                    await playlists.library.rename(playlist, to: name)
                }
            }
            .deletePlaylistConfirmation(
                playlistName: deleting?.name ?? "",
                isPresented: Binding(get: { playlists.deleting != nil }, set: { if !$0 { playlists.deleting = nil } }),
                hasDownloads: deleting.map { playlist in downloadedPlaylists.contains { $0.playlistId == playlist.id } } ?? false
            ) { purgeDownloads in
                guard let deleting else { return }
                Task {
                    if await playlists.library.delete(deleting, purgeDownloads: purgeDownloads),
                       navigator.selection == .playlist(id: deleting.id) {
                        navigator.selection = .albums
                    }
                }
            }
            .confirmationDialog("Already in Playlist",
                                isPresented: Binding(get: { playlists.pendingDuplicate != nil },
                                                     set: { if !$0 { playlists.pendingDuplicate = nil } }),
                                titleVisibility: .visible, presenting: playlists.pendingDuplicate) { pending in
                Button("Add Only New Songs") { playlists.resolveDuplicate(pending, skippingDuplicates: true) }
                Button("Add Anyway") { playlists.resolveDuplicate(pending, skippingDuplicates: false) }
                Button("Cancel", role: .cancel) { playlists.pendingDuplicate = nil }
            } message: { _ in
                Text("Some selected songs are already in this playlist.")
            }
    }
}

/// Asks for a playlist's name. `onSave` returns false to keep the sheet open after an error.
private struct MacPlaylistNameSheet: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    var message: LocalizedStringKey?
    var initialName = ""
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            TextField("Playlist Title", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(save)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!PlaylistLibraryViewModel.isValidName(name) || isSaving)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            name = initialName
            isNameFocused = true
        }
    }

    private func save() {
        guard PlaylistLibraryViewModel.isValidName(name), !isSaving else { return }
        isSaving = true
        Task {
            let saved = await onSave(name)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

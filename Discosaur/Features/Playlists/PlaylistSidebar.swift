import SwiftUI

struct PlaylistSidebar: View {
    let library: Library
    let onRename: (Playlist.ID, String) -> Void
    let onDelete: (Playlist.ID) -> Void
    @State private var playlistToDeleteID: Playlist.ID?

    private var playlistToDelete: Playlist? {
        playlistToDeleteID.flatMap { library.playlist(id: $0) }
    }

    private var selection: Binding<Playlist.ID?> {
        Binding(
            get: { library.selectedPlaylistID },
            set: { id in
                if let id { library.selectPlaylist(id: id) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                Section("Playlists") {
                    ForEach(library.playlists) { playlist in
                        PlaylistSidebarItem(
                            playlist: playlist,
                            selectedPlaylistID: library.selectedPlaylistID,
                            onRename: onRename,
                            onDelete: { playlistToDeleteID = $0 }
                        )
                        .tag(playlist.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("playlistSidebar")

            Divider()
            Button {
                library.createPlaylist()
            } label: {
                Label("New playlist", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(12)
            .help("Create an empty playlist")
            .accessibilityIdentifier("createPlaylistButton")
        }
        .confirmationDialog("Delete playlist?", isPresented: Binding(
            get: { playlistToDelete != nil },
            set: { if !$0 { playlistToDeleteID = nil } }
        ), titleVisibility: .visible, presenting: playlistToDelete) { playlist in
            Button("Delete", role: .destructive) {
                // Delete the requested playlist, not a browsing selection that can change.
                onDelete(playlist.id)
            }
            .accessibilityIdentifier("confirmDeletePlaylistButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("cancelDeletePlaylistButton")
        } message: { playlist in
            let count = playlist.tracks.count
            Text("Are you sure you want to delete this playlist? It has \(count) \(count == 1 ? "track" : "tracks").")
        }
    }
}

import SwiftUI

struct PlaylistSidebar: View {
    let library: Library
    let onRename: (Playlist.ID, String) -> Void

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
                            onRename: onRename
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
    }
}

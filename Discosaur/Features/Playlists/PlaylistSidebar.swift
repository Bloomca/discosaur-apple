import SwiftUI

struct PlaylistSidebar: View {
    let library: Library

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
                        Label(playlist.name, systemImage: "music.note.list")
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

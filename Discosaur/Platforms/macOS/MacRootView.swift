#if os(macOS)
import SwiftUI

struct MacRootView: View {
    let library: Library
    let player: Player
    @State private var selector: PlaylistSelector
    @State private var viewMode: PlaylistViewMode = .list
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(library: Library, fileAccessManager: FileAccessManager, player: Player) {
        self.library = library
        self.player = player
        _selector = State(initialValue: PlaylistSelector(library: library, fileAccessManager: fileAccessManager))
    }

    var body: some View {
        // NavigationSplitView supplies the standard sidebar toggle in the toolbar.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlaylistSidebar(library: library)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let playlist = library.selectedPlaylist {
                playlistContent
                    .navigationTitle(playlistName(for: playlist.id))
            } else {
                playlistContent
                    .navigationTitle("Discosaur")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 320)
    }

    private var playlistContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewMode {
            case .list:
                TrackList(playlist: library.selectedPlaylist, player: player)
            case .albums:
                AlbumGallery(playlist: library.selectedPlaylist, player: player)
            }

            Divider()
            PlayerView(player: player)
        }
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Playlist View", selection: $viewMode) {
                    Label("List", systemImage: "list.bullet")
                        .tag(PlaylistViewMode.list)
                    Label("Albums", systemImage: "square.grid.2x2")
                        .tag(PlaylistViewMode.albums)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Playlist view")
                .accessibilityIdentifier("playlistViewControls")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            if selector.isLoading {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Opening files/folders")
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItem(placement: .primaryAction) {
                SelectFilesButton { urls in
                    Task {
                        if let playlist = await selector.selectFiles(urls) {
                            player.updatePlaylist(playlist)
                        }
                    }
                }
                .disabled(selector.isLoading)
            }
        }
        .alert("Could not open files", isPresented: Binding(
            get: { selector.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    selector.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(selector.errorMessage ?? "")
        }
    }

    private func playlistName(for id: Playlist.ID) -> Binding<String> {
        // Capture the edited playlist's identity, not a selection that can change.
        Binding(
            get: { library.playlist(id: id)?.name ?? "Discosaur" },
            set: { name in
                library.renamePlaylist(id: id, to: name)
                if let playlist = library.playlist(id: id) {
                    // Refresh metadata only when this is the playing playlist.
                    player.updatePlaylist(playlist)
                }
            }
        )
    }
}

private enum PlaylistViewMode: Hashable {
    case list
    case albums
}

#Preview {
    let library = Library()
    let fileAccessManager = FileAccessManager(library: library)
    MacRootView(
        library: library,
        fileAccessManager: fileAccessManager,
        player: Player(engine: AVFilePlaybackEngine(), fileAccessManager: fileAccessManager)
    )
}
#endif

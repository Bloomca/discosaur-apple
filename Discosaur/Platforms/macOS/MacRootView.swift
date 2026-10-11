#if os(macOS)
import SwiftUI

struct MacRootView: View {
    let library: Library
    let artworkCache: AlbumArtworkCache
    let player: Player
    private let finderFileRevealer: FinderFileRevealer
    @State private var finderErrorMessage: String?
    @State private var selector: PlaylistSelector
    @State private var viewMode: PlaylistViewMode = .list
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(
        library: Library,
        fileAccessManager: FileAccessManager,
        artworkCache: AlbumArtworkCache,
        player: Player
    ) {
        self.library = library
        self.artworkCache = artworkCache
        self.player = player
        finderFileRevealer = FinderFileRevealer(fileAccessManager: fileAccessManager)
        _selector = State(initialValue: PlaylistSelector(library: library, fileAccessManager: fileAccessManager))
    }

    var body: some View {
        // NavigationSplitView supplies the standard sidebar toggle in the toolbar.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlaylistSidebar(library: library, onRename: renamePlaylist, onDelete: deletePlaylist)
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
        .task(id: library.selectedPlaylist) {
            if let playlist = library.selectedPlaylist {
                await artworkCache.load(for: playlist)
            }
        }
        .alert("Could not open in Finder", isPresented: Binding(
            get: { finderErrorMessage != nil },
            set: { isPresented in
                if !isPresented { finderErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(finderErrorMessage ?? "")
        }
    }

    private var playlistContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewMode {
            case .list:
                TrackList(
                    playlist: library.selectedPlaylist,
                    player: player,
                    onPlay: playTrack,
                    onDelete: deleteTrack,
                    onOpenInFinder: openInFinder
                )
            case .albums:
                AlbumGallery(playlist: library.selectedPlaylist, artworkCache: artworkCache, player: player)
            }

            Divider()
            PlayerView(player: player, artworkCache: artworkCache)
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

    private func playTrack(playlistID: Playlist.ID, trackID: Track.ID) {
        // Resolve the current contents, not the row/index captured by an open menu.
        guard let playlist = library.playlist(id: playlistID),
              let index = playlist.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        player.selectTrack(in: playlist, at: index)
        Task {
            guard player.activePlaylist?.id == playlistID, player.currentTrack?.id == trackID else { return }
            // Player publishes playback failures through its existing alert.
            try? await player.play()
        }
    }

    private func deletePlaylist(id: Playlist.ID) {
        guard library.removePlaylist(id: id) != nil else { return }
        player.removePlaylist(id: id)
    }

    private func deleteTrack(playlistID: Playlist.ID, trackID: Track.ID) {
        if let playlist = library.removeTrack(id: trackID, from: playlistID) {
            player.updatePlaylist(playlist)
        }
    }

    private func openInFinder(playlistID: Playlist.ID, trackID: Track.ID) {
        guard let track = library.playlist(id: playlistID)?.tracks.first(where: { $0.id == trackID }) else { return }
        finderErrorMessage = nil
        do {
            try finderFileRevealer.reveal(track)
        } catch {
            finderErrorMessage = error.localizedDescription
        }
    }

    private func playlistName(for id: Playlist.ID) -> Binding<String> {
        // Capture the edited playlist's identity, not a selection that can change.
        Binding(
            get: { library.playlist(id: id)?.name ?? "Discosaur" },
            set: { name in renamePlaylist(id: id, to: name) }
        )
    }

    private func renamePlaylist(id: Playlist.ID, to name: String) {
        library.renamePlaylist(id: id, to: name)
        if let playlist = library.playlist(id: id) {
            // Refresh metadata only when this is the playing playlist.
            player.updatePlaylist(playlist)
        }
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
        artworkCache: AlbumArtworkCache(fileAccessManager: fileAccessManager),
        player: Player(engine: AVFilePlaybackEngine(), fileAccessManager: fileAccessManager)
    )
}
#endif

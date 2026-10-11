#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct IOSRootView: View {
    let library: Library
    let artworkCache: AlbumArtworkCache
    let player: Player

    @State private var selector: PlaylistSelector
    @State private var preferredCompactColumn: NavigationSplitViewColumn
    @State private var isPresentingImporter = false
    @State private var importKind: IOSMusicImportKind = .files
    @State private var importPlaylistID: Playlist.ID?
    @State private var pickerErrorMessage: String?
    @State private var playlistToRenameID: Playlist.ID?
    @State private var playlistToDeleteID: Playlist.ID?
    @State private var playlistName = ""

    init(
        library: Library,
        fileAccessManager: FileAccessManager,
        artworkCache: AlbumArtworkCache,
        player: Player
    ) {
        self.library = library
        self.artworkCache = artworkCache
        self.player = player
        _selector = State(initialValue: PlaylistSelector(library: library, fileAccessManager: fileAccessManager))
        _preferredCompactColumn = State(initialValue: library.selectedPlaylist == nil ? .sidebar : .detail)
    }

    var body: some View {
        Group {
            if library.playlists.isEmpty {
                NavigationStack {
                    playlistList
                }
            } else {
                NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
                    playlistList
                        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
                } detail: {
                    if let playlistID = library.selectedPlaylistID {
                        IOSPlaylistDetailView(
                            playlistID: playlistID,
                            library: library,
                            artworkCache: artworkCache,
                            player: player,
                            isImporting: selector.isLoading,
                            onImport: beginImport,
                            onPlay: playTrack,
                            onDeleteTrack: deleteTrack,
                            onRename: beginRename,
                            onDelete: { playlistToDeleteID = $0 }
                        )
                        .id(playlistID)
                    } else {
                        ContentUnavailableView("Choose a playlist", systemImage: "music.note.list")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                MiniPlayerView(player: player, artworkCache: artworkCache)
            }
        }
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: importKind.contentTypes,
            allowsMultipleSelection: true,
            onCompletion: finishImport
        )
        .onChange(of: library.selectedPlaylistID) { _, id in
            if id != nil { preferredCompactColumn = .detail }
        }
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { clearErrors() } }
        )) {
            Button("OK", role: .cancel) { clearErrors() }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename playlist", isPresented: Binding(
            get: { playlistToRename != nil },
            set: { if !$0 { playlistToRenameID = nil } }
        ), presenting: playlistToRename) { playlist in
            TextField("Playlist name", text: $playlistName)
                .accessibilityIdentifier("playlistNameEditor")
            Button("Save") { renamePlaylist(id: playlist.id, to: playlistName) }
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete playlist?", isPresented: Binding(
            get: { playlistToDelete != nil },
            set: { if !$0 { playlistToDeleteID = nil } }
        ), titleVisibility: .visible, presenting: playlistToDelete) { playlist in
            Button("Delete", role: .destructive) { deletePlaylist(id: playlist.id) }
                .accessibilityIdentifier("confirmDeletePlaylistButton")
            Button("Cancel", role: .cancel) {}
        } message: { playlist in
            Text("Delete \u{201c}\(playlist.name)\u{201d}? Its audio files will not be deleted.")
        }
    }

    private var playlistList: some View {
        IOSPlaylistListView(
            library: library,
            selection: Binding(
                get: { library.selectedPlaylistID },
                set: { id in
                    // Going back to the list must not erase the remembered playlist.
                    if let id { library.selectPlaylist(id: id) }
                }
            ),
            isImporting: selector.isLoading,
            onCreate: createPlaylist,
            onImport: beginImport,
            onRename: beginRename,
            onDelete: { playlistToDeleteID = $0 }
        )
    }

    private var playlistToRename: Playlist? {
        playlistToRenameID.flatMap { library.playlist(id: $0) }
    }

    private var playlistToDelete: Playlist? {
        playlistToDeleteID.flatMap { library.playlist(id: $0) }
    }

    private var errorMessage: String? {
        pickerErrorMessage ?? selector.errorMessage ?? player.errorMessage
    }

    private var errorTitle: String {
        pickerErrorMessage != nil || selector.errorMessage != nil ? "Could not add music" : "Could not play track"
    }

    private func clearErrors() {
        pickerErrorMessage = nil
        selector.errorMessage = nil
        player.errorMessage = nil
    }

    private func createPlaylist() {
        library.createPlaylist()
        preferredCompactColumn = .detail
    }

    private func beginImport(_ kind: IOSMusicImportKind) {
        guard !selector.isLoading, !isPresentingImporter else { return }
        // Capture the destination before the picker opens, not when it returns.
        importPlaylistID = library.selectedPlaylistID
        importKind = kind
        pickerErrorMessage = nil
        isPresentingImporter = true
    }

    private func finishImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let destinationID = importPlaylistID
            Task {
                if let playlist = await selector.selectFiles(urls, into: destinationID) {
                    player.updatePlaylist(playlist)
                    if destinationID == nil {
                        library.selectPlaylist(id: playlist.id)
                        preferredCompactColumn = .detail
                    }
                }
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                pickerErrorMessage = error.localizedDescription
            }
        }
    }

    private func playTrack(playlistID: Playlist.ID, trackID: Track.ID) {
        // Resolve identities again; a row or menu may have outlived a library edit.
        guard let playlist = library.playlist(id: playlistID),
              let index = playlist.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        player.selectTrack(in: playlist, at: index)
        Task {
            guard player.activePlaylist?.id == playlistID, player.currentTrack?.id == trackID else { return }
            try? await player.play()
        }
    }

    private func deleteTrack(playlistID: Playlist.ID, trackID: Track.ID) {
        if let playlist = library.removeTrack(id: trackID, from: playlistID) {
            player.updatePlaylist(playlist)
        }
    }

    private func beginRename(id: Playlist.ID) {
        guard let playlist = library.playlist(id: id) else { return }
        playlistName = playlist.name
        playlistToRenameID = id
    }

    private func renamePlaylist(id: Playlist.ID, to name: String) {
        library.renamePlaylist(id: id, to: name.trimmingCharacters(in: .whitespacesAndNewlines))
        if let playlist = library.playlist(id: id) {
            player.updatePlaylist(playlist)
        }
    }

    private func deletePlaylist(id: Playlist.ID) {
        guard library.removePlaylist(id: id) != nil else { return }
        player.removePlaylist(id: id)
    }
}

enum IOSMusicImportKind {
    case files
    case folder

    var contentTypes: [UTType] {
        switch self {
        case .files: TrackScanner.audioContentTypes
        case .folder: [.folder]
        }
    }
}

struct IOSAddMusicMenu: View {
    let onImport: (IOSMusicImportKind) -> Void

    var body: some View {
        Menu {
            Button("Choose Files", systemImage: "doc") { onImport(.files) }
            Button("Choose Folder", systemImage: "folder") { onImport(.folder) }
        } label: {
            Label("Add Music", systemImage: "plus")
        }
        .accessibilityIdentifier("addMusicButton")
    }
}

#Preview {
    let library = Library()
    let fileAccessManager = FileAccessManager(library: library)
    IOSRootView(
        library: library,
        fileAccessManager: fileAccessManager,
        artworkCache: AlbumArtworkCache(fileAccessManager: fileAccessManager),
        player: Player(engine: AVFilePlaybackEngine(), fileAccessManager: fileAccessManager)
    )
}
#endif

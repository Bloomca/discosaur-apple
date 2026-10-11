#if os(iOS)
import SwiftUI

struct IOSPlaylistDetailView: View {
    let playlistID: Playlist.ID
    let library: Library
    let artworkCache: AlbumArtworkCache
    let player: Player
    let isImporting: Bool
    let onImport: (IOSMusicImportKind) -> Void
    let onPlay: (Playlist.ID, Track.ID) -> Void
    let onDeleteTrack: (Playlist.ID, Track.ID) -> Void
    let onRename: (Playlist.ID) -> Void
    let onDelete: (Playlist.ID) -> Void

    @State private var viewMode: ViewMode = .tracks

    private enum ViewMode {
        case tracks
        case albums
    }

    private var playlist: Playlist? { library.playlist(id: playlistID) }

    var body: some View {
        Group {
            if let playlist {
                if playlist.tracks.isEmpty {
                    ContentUnavailableView {
                        Label("Add music to this playlist", systemImage: "music.note.list")
                    } description: {
                        Text("Choose audio files or a folder from Files.")
                    } actions: {
                        IOSAddMusicMenu(onImport: onImport)
                            .buttonStyle(.borderedProminent)
                            .disabled(isImporting)
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("Playlist view", selection: $viewMode) {
                            Text("Tracks").tag(ViewMode.tracks)
                            Text("Albums").tag(ViewMode.albums)
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .accessibilityIdentifier("playlistViewControls")

                        switch viewMode {
                        case .tracks:
                            TrackList(
                                playlist: playlist,
                                player: player,
                                onPlay: onPlay,
                                onDelete: onDeleteTrack
                            )
                            .listStyle(.plain)
                        case .albums:
                            AlbumGallery(playlist: playlist, artworkCache: artworkCache, player: player)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Playlist not found", systemImage: "music.note.list")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isImporting {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView()
                        .accessibilityLabel("Adding music")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Choose Files", systemImage: "doc") { onImport(.files) }
                        .disabled(isImporting)
                    Button("Choose Folder", systemImage: "folder") { onImport(.folder) }
                        .disabled(isImporting)
                    Divider()
                    Button("Rename Playlist", systemImage: "pencil") { onRename(playlistID) }
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) { onDelete(playlistID) }
                } label: {
                    Label("Playlist actions", systemImage: "ellipsis")
                }
                .disabled(playlist == nil)
                .accessibilityIdentifier("playlistActionsButton")
            }
        }
        .task(id: playlist) {
            if let playlist { await artworkCache.load(for: playlist) }
        }
    }
}
#endif

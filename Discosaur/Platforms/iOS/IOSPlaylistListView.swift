#if os(iOS)
import SwiftUI

struct IOSPlaylistListView: View {
    let library: Library
    let selection: Binding<Playlist.ID?>
    let isImporting: Bool
    let onCreate: () -> Void
    let onImport: (IOSMusicImportKind) -> Void
    let onRename: (Playlist.ID) -> Void
    let onDelete: (Playlist.ID) -> Void

    var body: some View {
        Group {
            if library.playlists.isEmpty {
                ContentUnavailableView {
                    Label("Add your music", systemImage: "music.note")
                } description: {
                    Text("Choose audio files or a folder from Files to start your library.")
                } actions: {
                    IOSAddMusicMenu(onImport: onImport)
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting)
                }
            } else {
                List(selection: selection) {
                    ForEach(library.playlists) { playlist in
                        NavigationLink(value: playlist.id) {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .lineLimit(1)
                                    Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "track" : "tracks")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .tag(playlist.id)
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { onRename(playlist.id) }
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(playlist.id) }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(playlist.id) }
                            Button("Rename", systemImage: "pencil") { onRename(playlist.id) }
                                .tint(.blue)
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("iosPlaylistList")
            }
        }
        .navigationTitle("Playlists")
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
                    Button("New Playlist", systemImage: "music.note.list", action: onCreate)
                        .accessibilityIdentifier("createPlaylistButton")
                } label: {
                    Label("Library actions", systemImage: "plus")
                }
                .accessibilityIdentifier("libraryActionsButton")
            }
        }
    }
}
#endif

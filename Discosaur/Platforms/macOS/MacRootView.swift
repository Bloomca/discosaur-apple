#if os(macOS)
import SwiftUI

struct MacRootView: View {
    let library: Library
    @State private var selector: PlaylistSelector
    @State private var viewMode: PlaylistViewMode = .list

    init(library: Library) {
        self.library = library
        _selector = State(initialValue: PlaylistSelector(library: library))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewMode {
            case .list:
                TrackList(playlist: library.currentPlaylist)
            case .albums:
                AlbumGallery(playlist: library.currentPlaylist)
            }

            Divider()
            PlayerView()
        }
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            ToolbarSpacer(.flexible, placement: .primaryAction)
            
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
                            Player.shared.updatePlaylist(playlist)
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
}

private enum PlaylistViewMode: Hashable {
    case list
    case albums
}

#Preview {
    MacRootView(library: Library())
}
#endif

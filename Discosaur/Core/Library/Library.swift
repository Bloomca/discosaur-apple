import Foundation
import Observation

@MainActor
@Observable
final class Library {
    private(set) var playlists: [Playlist] = []
    private(set) var sources: [FileSource] = []
    private(set) var selectedPlaylistID: UUID?

    // Browsing selection is independent of Player.activePlaylist and its queue.
    var selectedPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return playlist(id: selectedPlaylistID)
    }

    func playlist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    func source(id: UUID) -> FileSource? {
        sources.first { $0.id == id }
    }

    func updateSource(_ source: FileSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
    }

    // Insert or replace a playlist, selecting only the first one added.
    func updatePlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }

        if selectedPlaylistID == nil {
            selectedPlaylistID = playlist.id
        }
    }

    func selectPlaylist(id: UUID) {
        guard playlist(id: id) != nil else { return }
        selectedPlaylistID = id
    }

    @discardableResult
    func createPlaylist() -> Playlist {
        let playlist = Playlist(tracks: [])
        updatePlaylist(playlist)
        selectPlaylist(id: playlist.id)
        return playlist
    }

    func renamePlaylist(id: UUID, to name: String) {
        guard let playlist = playlist(id: id), playlist.name != name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        updatePlaylist(Playlist(id: playlist.id, name: name, tracks: playlist.tracks))
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class Library {
    private(set) var playlists: [Playlist] = []
    private(set) var sources: [FileSource] = []
    private(set) var currentPlaylistID: UUID?

    var currentPlaylist: Playlist? {
        guard let currentPlaylistID else { return nil }
        return playlist(id: currentPlaylistID)
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

        if currentPlaylistID == nil {
            currentPlaylistID = playlist.id
        }
    }

    func selectPlaylist(id: UUID) {
        guard playlist(id: id) != nil else { return }
        currentPlaylistID = id
    }
}

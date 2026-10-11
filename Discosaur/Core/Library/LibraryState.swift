import Foundation

nonisolated struct LibraryState: Equatable, Sendable {
    let selectedPlaylistID: Playlist.ID?
    let activePlaylistID: Playlist.ID?
    let currentTrackID: Track.ID?

    init(
        selectedPlaylistID: Playlist.ID? = nil,
        activePlaylistID: Playlist.ID? = nil,
        currentTrackID: Track.ID? = nil
    ) {
        self.selectedPlaylistID = selectedPlaylistID
        self.activePlaylistID = activePlaylistID
        self.currentTrackID = currentTrackID
    }
}

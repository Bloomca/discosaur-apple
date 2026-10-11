import Foundation
import Observation

@MainActor
final class LibraryStatePersistence {
    private let library: Library
    private let player: Player
    private let storage: any LibraryStateStoring
    private var isStarted = false
    private var lastSavedState: LibraryState?

    init(library: Library, player: Player, storage: any LibraryStateStoring) {
        self.library = library
        self.player = player
        self.storage = storage
    }

    // Called only after the JSON library has loaded successfully. Do not observe
    // the temporary empty/default selection or partially restored playback pair.
    func restoreAndStart() {
        guard !isStarted else { return }
        let saved = storage.load()
        let selectedID = saved.selectedPlaylistID.flatMap { library.playlist(id: $0)?.id }
            ?? library.playlists.first?.id
        if let selectedID { library.selectPlaylist(id: selectedID) }
        player.stop()
        if let playlistID = saved.activePlaylistID,
           let trackID = saved.currentTrackID,
           let playlist = library.playlist(id: playlistID),
           let index = playlist.tracks.firstIndex(where: { $0.id == trackID }) {
            // Selecting restores the full queue, stopped at zero, without opening
            // audio or resolving bookmarks. Album-only navigation is not persisted.
            player.selectTrack(in: playlist, at: index)
        }
        isStarted = true
        observeChanges()
        // Normalize stale/malformed references only after restoration is complete.
        flush()
    }

    func flush() {
        guard isStarted else { return }
        let state = currentState
        guard state != lastSavedState else { return }
        storage.save(state)
        lastSavedState = state
    }

    private var currentState: LibraryState {
        let selectedID = library.selectedPlaylistID
        if let playlistID = player.activePlaylist?.id,
           let trackID = player.currentTrack?.id,
           let playlist = library.playlist(id: playlistID),
           playlist.tracks.contains(where: { $0.id == trackID }) {
            return LibraryState(selectedPlaylistID: selectedID, activePlaylistID: playlistID, currentTrackID: trackID)
        }
        return LibraryState(selectedPlaylistID: selectedID)
    }

    private func observeChanges() {
        withObservationTracking {
            _ = currentState
        } onChange: { [weak self] in
            // Observation fires before mutation. Defer until the main-actor turn
            // finishes so create/delete/select operations produce one stable snapshot.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeChanges()
                self.flush()
            }
        }
    }
}

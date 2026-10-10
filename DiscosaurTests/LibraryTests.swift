import Foundation
import Observation
import Synchronization
import Testing
@testable import Discosaur

@MainActor
struct LibraryTests {
    @Test func startsWithoutPlaylistsOrSelection() {
        let library = Library()

        #expect(library.playlists.isEmpty)
        #expect(library.currentPlaylistID == nil)
        #expect(library.currentPlaylist == nil)
    }

    @Test func firstPlaylistBecomesCurrent() {
        let library = Library()
        let playlist = Playlist(tracks: [])

        library.updatePlaylist(playlist)

        #expect(library.playlists == [playlist])
        #expect(library.currentPlaylistID == playlist.id)
        #expect(library.currentPlaylist == playlist)
        #expect(library.playlist(id: playlist.id) == playlist)
    }

    @Test func addingAnotherPlaylistPreservesSelectionAndInsertionOrder() {
        let library = Library()
        let first = Playlist(tracks: [])
        let second = Playlist(tracks: [])

        library.updatePlaylist(first)
        library.updatePlaylist(second)

        #expect(library.playlists == [first, second])
        #expect(library.currentPlaylist == first)
        #expect(library.playlist(id: second.id) == second)
    }

    @Test func replacingCurrentPlaylistPreservesIdentityAndSelection() {
        let library = Library()
        let original = Playlist(tracks: [])
        let other = Playlist(tracks: [])
        library.updatePlaylist(original)
        library.updatePlaylist(other)
        let updated = Playlist(
            id: original.id,
            tracks: [Track(url: URL(fileURLWithPath: "/Music/song.mp3"))]
        )

        library.updatePlaylist(updated)

        #expect(library.playlists == [updated, other])
        #expect(library.currentPlaylistID == original.id)
        #expect(library.currentPlaylist == updated)
    }

    @Test func selectingAnotherPlaylistAndUpdatingThePreviousOnePreservesSelection() {
        let library = Library()
        let first = Playlist(tracks: [])
        let second = Playlist(tracks: [])
        library.updatePlaylist(first)
        library.updatePlaylist(second)

        library.selectPlaylist(id: second.id)
        let updated = Playlist(
            id: first.id,
            tracks: [Track(url: URL(fileURLWithPath: "/Music/song.mp3"))]
        )
        library.updatePlaylist(updated)

        #expect(library.currentPlaylistID == second.id)
        #expect(library.currentPlaylist == second)
        #expect(library.playlists == [updated, second])
    }

    @Test func unknownPlaylistCannotBecomeCurrent() {
        let library = Library()
        let unknownID = UUID()
        library.selectPlaylist(id: unknownID)
        #expect(library.currentPlaylist == nil)

        let playlist = Playlist(tracks: [])
        library.updatePlaylist(playlist)
        library.selectPlaylist(id: unknownID)

        #expect(library.currentPlaylist == playlist)
        #expect(library.playlist(id: unknownID) == nil)
    }

    @Test func currentPlaylistUpdatesAreObservable() {
        let library = Library()
        let original = Playlist(tracks: [])
        library.updatePlaylist(original)
        let didChange = Mutex(false)
        withObservationTracking {
            _ = library.currentPlaylist
        } onChange: {
            didChange.withLock { $0 = true }
        }

        library.updatePlaylist(Playlist(
            id: original.id,
            tracks: [Track(url: URL(fileURLWithPath: "/Music/song.mp3"))]
        ))

        #expect(didChange.withLock { $0 })
    }
}

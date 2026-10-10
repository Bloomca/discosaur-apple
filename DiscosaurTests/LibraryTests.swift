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
        #expect(library.selectedPlaylistID == nil)
        #expect(library.selectedPlaylist == nil)
    }

    @Test func firstPlaylistBecomesSelected() {
        let library = Library()
        let playlist = Playlist(tracks: [])

        library.updatePlaylist(playlist)

        #expect(library.playlists == [playlist])
        #expect(library.selectedPlaylistID == playlist.id)
        #expect(library.selectedPlaylist == playlist)
        #expect(library.playlist(id: playlist.id) == playlist)
    }

    @Test func addingAnotherPlaylistPreservesSelectionAndInsertionOrder() {
        let library = Library()
        let first = Playlist(tracks: [])
        let second = Playlist(tracks: [])

        library.updatePlaylist(first)
        library.updatePlaylist(second)

        #expect(library.playlists == [first, second])
        #expect(library.selectedPlaylist == first)
        #expect(library.playlist(id: second.id) == second)
    }

    @Test func replacingSelectedPlaylistPreservesIdentityAndSelection() {
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
        #expect(library.selectedPlaylistID == original.id)
        #expect(library.selectedPlaylist == updated)
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

        #expect(library.selectedPlaylistID == second.id)
        #expect(library.selectedPlaylist == second)
        #expect(library.playlists == [updated, second])
    }

    @Test func unknownPlaylistCannotBecomeSelected() {
        let library = Library()
        let unknownID = UUID()
        library.selectPlaylist(id: unknownID)
        #expect(library.selectedPlaylist == nil)

        let playlist = Playlist(tracks: [])
        library.updatePlaylist(playlist)
        library.selectPlaylist(id: unknownID)

        #expect(library.selectedPlaylist == playlist)
        #expect(library.playlist(id: unknownID) == nil)
    }

    @Test func selectedPlaylistUpdatesAreObservable() {
        let library = Library()
        let original = Playlist(tracks: [])
        library.updatePlaylist(original)
        let didChange = Mutex(false)
        withObservationTracking {
            _ = library.selectedPlaylist
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

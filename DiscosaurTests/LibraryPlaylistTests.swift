import Foundation
import Observation
import Synchronization
import Testing
@testable import Discosaur

@MainActor
struct LibraryPlaylistTests {
    @Test func creatingPlaylistsSelectsEachNewEmptyPlaylistWithAUniqueIdentity() {
        let library = Library()
        let first = library.createPlaylist()
        library.renamePlaylist(id: first.id, to: "Favourites")
        let renamed = library.playlist(id: first.id)
        let second = library.createPlaylist()

        #expect(second.name == "New playlist")
        #expect(second.tracks.isEmpty)
        #expect(library.playlists.first == renamed)
        #expect(library.selectedPlaylistID == second.id)
        #expect(library.selectedPlaylist == second)
        let third = library.createPlaylist()
        #expect(library.playlists.map(\.id) == [first.id, second.id, third.id])
        #expect(Set(library.playlists.map(\.id)).count == 3)
        #expect(library.selectedPlaylist == third)
    }

    @Test func renamingPreservesTracksIdentityOrderAndBrowsingSelection() {
        let library = Library()
        let tracks = [Track(url: URL(fileURLWithPath: "/Music/song.mp3"))]
        let original = Playlist(name: "Original", tracks: tracks)
        library.updatePlaylist(original)
        let selected = library.createPlaylist()

        library.renamePlaylist(id: original.id, to: "My favourites")

        let renamed = Playlist(id: original.id, name: "My favourites", tracks: tracks)
        #expect(library.playlists == [renamed, selected])
        #expect(library.playlist(id: original.id) == renamed)
        #expect(library.selectedPlaylistID == selected.id)
        #expect(library.selectedPlaylist == selected)
    }

    @Test(arguments: ["", " ", "\t\n"])
    func emptyNamesDoNotReplaceTheExistingName(name: String) {
        let library = Library()
        let original = library.createPlaylist()

        library.renamePlaylist(id: original.id, to: name)

        #expect(library.playlists == [original])
        #expect(library.selectedPlaylist == original)
    }

    @Test func renamingAnUnknownPlaylistDoesNotInsertItOrChangeSelection() {
        let library = Library()
        library.renamePlaylist(id: UUID(), to: "Unknown")
        #expect(library.playlists.isEmpty)
        #expect(library.selectedPlaylist == nil)
        let original = library.createPlaylist()

        library.renamePlaylist(id: UUID(), to: "Unknown")

        #expect(library.playlists == [original])
        #expect(library.selectedPlaylist == original)
    }

    @Test func selectedPlaylistNameChangesAreObservable() {
        let library = Library()
        let original = library.createPlaylist()
        let didChange = Mutex(false)
        withObservationTracking {
            _ = library.selectedPlaylist?.name
        } onChange: {
            didChange.withLock { $0 = true }
        }

        library.renamePlaylist(id: original.id, to: "Renamed")

        #expect(didChange.withLock { $0 })
        #expect(library.selectedPlaylist?.name == "Renamed")
    }
}

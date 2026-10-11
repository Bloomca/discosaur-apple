import Foundation
import Observation
import Synchronization
import Testing
@testable import Discosaur

@MainActor
struct LibraryPlaylistRemovalTests {
    @Test(arguments: [0, 1, 2])
    func deletingSelectedPlaylistSelectsNextOrPreviousAndPreservesOrder(index: Int) throws {
        let library = Library()
        let playlists = (0..<3).map { Playlist(name: "Playlist \($0)", tracks: []) }
        for playlist in playlists { library.updatePlaylist(playlist) }
        library.selectPlaylist(id: playlists[index].id)

        let removed = library.removePlaylist(id: playlists[index].id)

        var remaining = playlists
        remaining.remove(at: index)
        #expect(removed == playlists[index])
        #expect(library.playlists == remaining)
        #expect(library.selectedPlaylist == remaining[min(index, remaining.count - 1)])
        #expect(library.playlist(id: playlists[index].id) == nil)
    }

    @Test func deletingAnUnselectedPlaylistPreservesTheBrowsingSelection() {
        let library = Library()
        let first = library.createPlaylist()
        let selected = library.createPlaylist()
        let last = library.createPlaylist()
        library.selectPlaylist(id: selected.id)

        library.removePlaylist(id: first.id)

        #expect(library.playlists == [selected, last])
        #expect(library.selectedPlaylist == selected)
    }

    @Test func deletingTheLastPlaylistClearsSelectionAndNotifiesOnce() {
        let library = Library()
        let playlist = library.createPlaylist()
        var changes = 0
        library.onChange = { changes += 1 }

        #expect(library.removePlaylist(id: playlist.id) == playlist)

        #expect(library.playlists.isEmpty)
        #expect(library.selectedPlaylistID == nil)
        #expect(library.selectedPlaylist == nil)
        #expect(changes == 1)
        library.createPlaylist()
        #expect(library.selectedPlaylist != nil)
    }

    @Test func deletingUnknownOrAlreadyDeletedPlaylistsIsANoOp() {
        let library = Library()
        let playlist = library.createPlaylist()
        var changes = 0
        library.onChange = { changes += 1 }

        #expect(library.removePlaylist(id: UUID()) == nil)
        #expect(library.playlists == [playlist])
        #expect(library.selectedPlaylist == playlist)
        #expect(changes == 0)
        library.removePlaylist(id: playlist.id)
        #expect(library.removePlaylist(id: playlist.id) == nil)
        #expect(changes == 1)
    }

    @Test func deletingAPlaylistPreservesFilesArtworkBookmarksAndSharedTracks() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let song = try fixture.file("Album/song.mp3")
        let cover = try fixture.file("Album/cover.jpg")
        let source = FileSource(kind: .folder, bookmarkData: Data([1, 2, 3]))
        let album = Album(title: "Album", artist: nil, year: nil, coverLocation: .insideFolder(sourceID: source.id, relativePath: "cover.jpg"))
        let track = Track(url: song, metadata: TrackMetadata(), album: album, location: .insideFolder(sourceID: source.id, relativePath: "song.mp3"))
        let deleted = Playlist(name: "Deleted", tracks: [track])
        let shared = Playlist(name: "Shared", tracks: [track])
        let library = Library()
        library.updateSource(source)
        library.updatePlaylist(deleted)
        library.updatePlaylist(shared)

        library.removePlaylist(id: deleted.id)

        #expect(library.playlists == [shared])
        #expect(library.sources == [source])
        #expect(FileManager.default.fileExists(atPath: song.path))
        #expect(FileManager.default.fileExists(atPath: cover.path))
        library.removePlaylist(id: shared.id)
        #expect(library.sources == [source])
    }

    @Test func deletingSelectedPlaylistIsObservable() {
        let library = Library()
        let playlist = library.createPlaylist()
        let didChange = Mutex(false)
        withObservationTracking {
            _ = library.selectedPlaylist
        } onChange: {
            didChange.withLock { $0 = true }
        }

        library.removePlaylist(id: playlist.id)

        #expect(didChange.withLock { $0 })
    }
}

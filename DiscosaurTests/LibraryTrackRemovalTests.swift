import Foundation
import Testing
@testable import Discosaur

@MainActor
struct LibraryTrackRemovalTests {
    @Test func removalPreservesIdentityNameOrderSelectionAndSharedReferences() throws {
        let library = Library()
        let source = FileSource(kind: .file, bookmarkData: Data("bookmark".utf8))
        library.updateSource(source)
        let first = Track(url: URL(fileURLWithPath: "/Music/first.mp3"))
        let removed = Track(url: URL(fileURLWithPath: "/Music/shared.mp3"), location: .selectedFile(sourceID: source.id))
        let last = Track(url: URL(fileURLWithPath: "/Music/last.mp3"))
        let original = Playlist(name: "Favourites", tracks: [first, removed, last])
        let other = Playlist(name: "Other", tracks: [removed])
        library.updatePlaylist(original)
        library.updatePlaylist(other)
        library.selectPlaylist(id: other.id)

        let updated = try #require(library.removeTrack(id: removed.id, from: original.id))

        #expect(updated == Playlist(id: original.id, name: "Favourites", tracks: [first, last]))
        #expect(library.playlists == [updated, other])
        #expect(library.selectedPlaylist == other)
        #expect(library.sources == [source])
    }

    @Test func removingTheLastTrackKeepsTheEmptyPlaylistSelected() throws {
        let library = Library()
        let track = Track(url: URL(fileURLWithPath: "/Music/song.mp3"))
        let original = Playlist(name: "Favourites", tracks: [track])
        library.updatePlaylist(original)

        let updated = try #require(library.removeTrack(id: track.id, from: original.id))

        #expect(updated.id == original.id)
        #expect(updated.name == original.name)
        #expect(updated.tracks.isEmpty)
        #expect(library.playlists == [updated])
        #expect(library.selectedPlaylist == updated)
    }

    @Test func unknownTracksAndPlaylistsLeaveTheLibraryUnchanged() {
        let library = Library()
        let track = Track(url: URL(fileURLWithPath: "/Music/song.mp3"))
        let original = Playlist(tracks: [track])
        library.updatePlaylist(original)

        #expect(library.removeTrack(id: track.id, from: UUID()) == nil)
        #expect(library.removeTrack(id: URL(fileURLWithPath: "/Music/missing.mp3"), from: original.id) == nil)
        #expect(library.playlists == [original])
        #expect(library.selectedPlaylist == original)
    }

    @Test func removalUsesLatestContentsAndNameInsteadOfAStaleRowIndex() throws {
        let library = Library()
        let first = Track(url: URL(fileURLWithPath: "/Music/first.mp3"))
        let removed = Track(url: URL(fileURLWithPath: "/Music/removed.mp3"))
        let added = Track(url: URL(fileURLWithPath: "/Music/added.mp3"))
        let original = Playlist(name: "Original", tracks: [first, removed])
        library.updatePlaylist(original)
        library.updatePlaylist(Playlist(id: original.id, name: "Renamed", tracks: [added, first, removed]))

        let updated = try #require(library.removeTrack(id: removed.id, from: original.id))

        #expect(updated.name == "Renamed")
        #expect(updated.tracks == [added, first])
        #expect(library.selectedPlaylist == updated)
    }

    @Test func removingAnEntryDoesNotDeleteItsFile() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("song.mp3")
        let library = Library()
        let original = Playlist(tracks: [Track(url: url)])
        library.updatePlaylist(original)

        library.removeTrack(id: url, from: original.id)

        #expect(library.selectedPlaylist?.tracks.isEmpty == true)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

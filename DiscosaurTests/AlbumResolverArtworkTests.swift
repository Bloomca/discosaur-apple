import Foundation
import Testing
@testable import Discosaur

struct AlbumResolverArtworkTests {
    @Test func folderArtworkIsDiscoveredAsARelativeReferenceWithoutReadingImageBytes() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let folder = try fixture.folder("Album")
        let track = try fixture.file("Album/01.mp3")
        // Empty files deliberately demonstrate that discovery does not read/decode images.
        _ = try fixture.file("Album/COVER.JPG")
        _ = try fixture.file("Album/folder.jpg")
        let sourceID = UUID()

        let tracks = try await AlbumResolver().resolve(
            [(url: track, metadata: TrackMetadata(album: "Album"), location: nil)],
            selectedFolders: [(url: folder, sourceID: sourceID)]
        )

        #expect(tracks.first?.album?.coverLocation == .insideFolder(sourceID: sourceID, relativePath: "COVER.JPG"))
    }

    @Test func nestedFoldersUseTheMostSpecificGrantAndFolderJPGFallback() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let parent = try fixture.folder("Collection")
        let album = try fixture.folder("Collection/Album")
        let track = try fixture.file("Collection/Album/Disc 1/01.mp3")
        _ = try fixture.file("Collection/Album/Disc 1/folder.jpg")
        let sourceID = UUID()

        let tracks = try await AlbumResolver().resolve(
            [(url: track, metadata: TrackMetadata(album: "Album"), location: nil)],
            selectedFolders: [(url: parent, sourceID: UUID()), (url: album, sourceID: sourceID)]
        )

        #expect(tracks.first?.album?.coverLocation == .insideFolder(sourceID: sourceID, relativePath: "Disc 1/folder.jpg"))
    }

    @Test func fileOnlyImportsDoNotDiscoverSiblingArtwork() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let track = try fixture.file("Album/01.mp3")
        _ = try fixture.file("Album/cover.jpg")

        let tracks = try await AlbumResolver().resolve(
            [(url: track, metadata: TrackMetadata(album: "Album"), location: nil)],
            selectedFolders: []
        )

        #expect(tracks.first?.album?.coverLocation == nil)
    }

    @Test func symlinksCannotAuthorizeArtworkOutsideTheSelectedFolder() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let folder = try fixture.folder("Album")
        let track = try fixture.file("Album/01.mp3")
        let outside = try fixture.file("Outside/cover.jpg")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("cover.jpg"), withDestinationURL: outside)

        let tracks = try await AlbumResolver().resolve(
            [(url: track, metadata: TrackMetadata(album: "Album"), location: nil)],
            selectedFolders: [(url: folder, sourceID: UUID())]
        )

        #expect(tracks.first?.album?.coverLocation == nil)
    }
}

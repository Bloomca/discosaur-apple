import Foundation
import Testing
@testable import Discosaur

@MainActor
struct PlaylistSelectorFileAccessTests {
    @Test func folderImportAttachesSharedRelativeLocationsAndPreservesMetadata() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let folder = try fixture.folder("Album")
        let first = try fixture.file("Album/Disc 1/01.mp3")
        let second = try fixture.file("Album/Disc 2/01.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )

        let imported = try #require(await selector.selectFiles([folder]))
        let source = try #require(library.sources.first)
        #expect(library.sources.count == 1)
        #expect(source.kind == .folder)
        #expect(imported.tracks.map(\.url) == [first, second])
        #expect(imported.tracks.map(\.location) == [
            .insideFolder(sourceID: source.id, relativePath: "Disc 1/01.mp3"),
            .insideFolder(sourceID: source.id, relativePath: "Disc 2/01.mp3"),
        ])
        #expect(imported.tracks.allSatisfy { $0.title == "Selected track" && $0.duration == 42 })
        #expect(imported.tracks.allSatisfy { $0.album?.title == "Album" })
        #expect(backend.startedURLs == [folder])
        #expect(backend.stoppedURLs == [folder])

        let location = try #require(imported.tracks.first?.location)
        let access = try manager.acquire(location)
        #expect(access.resourceURL == first)
        #expect(backend.startedURLs == [folder, folder])
        access.close()
        #expect(backend.stoppedURLs == [folder, folder])
    }

    @Test func fileOnlyImportUsesAFileSource() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let file = try fixture.file("Album/song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )

        let imported = try #require(await selector.selectFiles([file]))
        let source = try #require(library.sources.first)
        #expect(source.kind == .file)
        #expect(imported.tracks.first?.location == .selectedFile(sourceID: source.id))
        #expect(backend.startedURLs == [file])
        #expect(backend.stoppedURLs == [file])
    }

    @Test func overlappingSelectionsPreferFoldersAndCommitOnlyUsedSources() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let folder = try fixture.folder("Album")
        let child = try fixture.file("Album/song.mp3")
        let outside = try fixture.file("Other/song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )

        let imported = try #require(await selector.selectFiles([child, folder, outside]))
        let folderSource = try #require(library.sources.first { $0.kind == .folder })
        let fileSource = try #require(library.sources.first { $0.kind == .file })
        #expect(library.sources.count == 2)
        #expect(imported.tracks.count == 2)
        #expect(imported.tracks.first { $0.url == child }?.location ==
            .insideFolder(sourceID: folderSource.id, relativePath: "song.mp3"))
        #expect(imported.tracks.first { $0.url == outside }?.location == .selectedFile(sourceID: fileSource.id))
        #expect(backend.startedURLs.count == backend.stoppedURLs.count)
    }

    @Test func nestedFolderSelectionsUseTheMostSpecificSource() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let parent = try fixture.folder("Collection")
        let album = try fixture.folder("Collection/Album")
        _ = try fixture.file("Collection/Album/song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )

        let imported = try #require(await selector.selectFiles([parent, album]))
        let source = try #require(library.sources.first)
        #expect(library.sources.count == 1)
        #expect(try backend.resolveBookmark(source.bookmarkData).url == album)
        #expect(imported.tracks.first?.location == .insideFolder(sourceID: source.id, relativePath: "song.mp3"))
        #expect(backend.startedURLs.count == backend.stoppedURLs.count)
    }

    @Test func folderSourcesAreReusedAcrossPlaylists() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let folder = try fixture.folder("Album")
        _ = try fixture.file("Album/song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )
        let first = try #require(await selector.selectFiles([folder]))
        let originalSourceID = try #require(library.sources.first?.id)
        let second = Playlist(tracks: [])
        library.updatePlaylist(second)
        library.selectPlaylist(id: second.id)

        let imported = try #require(await selector.selectFiles([folder]))
        #expect(library.sources.count == 1)
        #expect(library.sources.first?.id == originalSourceID)
        #expect(imported.tracks.first?.location == first.tracks.first?.location)
        #expect(library.playlist(id: first.id) == first)
        #expect(backend.startedURLs.count == backend.stoppedURLs.count)
    }

    @Test func failedPartialImportsLeaveNoSourcesAndReleaseAllSelections() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let file = try fixture.file("song.mp3")
        let missing = fixture.directory.appendingPathComponent("missing.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )

        #expect(await selector.selectFiles([file, missing]) == nil)
        #expect(library.sources.isEmpty)
        #expect(library.playlists.isEmpty)
        #expect(selector.errorMessage != nil)
        #expect(backend.startedURLs == [file, missing])
        #expect(backend.stoppedURLs == [missing, file])
    }

    @Test func cancelledImportsLeaveNoSourcesAndReleaseAccess() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let file = try fixture.file("song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend, cancels: true)
        )

        #expect(await selector.selectFiles([file]) == nil)
        #expect(library.sources.isEmpty)
        #expect(library.playlists.isEmpty)
        #expect(selector.errorMessage == nil)
        #expect(backend.startedURLs == [file])
        #expect(backend.stoppedURLs == [file])
    }

    @Test func duplicateAndEmptyImportsDoNotAddOrReplaceSources() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let file = try fixture.file("song.mp3")
        let empty = try fixture.folder("Empty")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        let selector = PlaylistSelector(
            library: library,
            fileAccessManager: manager,
            metadataReader: ScopedSelectionMetadataReader(backend: backend)
        )
        await selector.selectFiles([file])
        let originalSources = library.sources
        let originalPlaylists = library.playlists

        #expect(await selector.selectFiles([file, file]) == nil)
        #expect(await selector.selectFiles([empty]) == nil)
        #expect(library.sources == originalSources)
        #expect(library.playlists == originalPlaylists)
        #expect(backend.startedURLs.count == backend.stoppedURLs.count)
    }
}

private struct ScopedSelectionMetadataReader: TrackMetadataReading {
    let backend: TestFileAccessBackend
    var cancels = false

    func read(at url: URL) async throws -> TrackMetadata {
        await MainActor.run {
            #expect(backend.startedURLs.count > backend.stoppedURLs.count)
        }
        if cancels { throw CancellationError() }
        return TrackMetadata(title: "Selected track", album: "Album", duration: 42)
    }
}

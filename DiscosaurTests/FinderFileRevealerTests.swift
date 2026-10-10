#if os(macOS)
import Foundation
import Testing
@testable import Discosaur

@MainActor
struct FinderFileRevealerTests {
    @Test func selectedFileUsesItsResolvedLocationAndHoldsAccessThroughTheRequest() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let resolvedURL = try fixture.file("Moved/song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: resolvedURL))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)
        var revealedURLs: [URL] = []
        let revealer = FinderFileRevealer(fileAccessManager: manager) { urls in
            #expect(backend.startedURLs == [resolvedURL])
            #expect(backend.stoppedURLs.isEmpty)
            revealedURLs = urls
        }
        let track = Track(
            url: URL(fileURLWithPath: "/Music/Old/song.mp3"),
            location: .selectedFile(sourceID: source.id)
        )

        try revealer.reveal(track)

        #expect(revealedURLs == [resolvedURL])
        #expect(backend.stoppedURLs == [resolvedURL])
    }

    @Test func folderTrackUsesTheResolvedRootAndRefreshesAStaleBookmark() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let root = try fixture.folder("Moved Album")
        let resolvedURL = try fixture.file("Moved Album/Disc 1/Song #1.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root, isStale: true))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)
        var revealedURLs: [URL] = []
        let revealer = FinderFileRevealer(fileAccessManager: manager) { urls in
            #expect(backend.startedURLs == [root])
            #expect(backend.stoppedURLs.isEmpty)
            revealedURLs = urls
        }
        let track = Track(
            url: URL(fileURLWithPath: "/Music/Old Album/Disc 1/Song #1.mp3"),
            location: .insideFolder(sourceID: source.id, relativePath: "Disc 1/Song #1.mp3")
        )

        try revealer.reveal(track)

        #expect(revealedURLs == [resolvedURL])
        #expect(library.source(id: source.id)?.bookmarkData != source.bookmarkData)
        #expect(backend.bookmarkedURLs == [root])
        #expect(backend.stoppedURLs == [root])
    }

    @Test func legacyLocalTracksUseTheirURLWithoutStoppingAnUnstartedScope() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("song.mp3")
        let backend = TestFileAccessBackend()
        backend.startsSucceed = false
        let manager = FileAccessManager(library: Library(), backend: backend)
        var revealedURLs: [URL] = []
        let revealer = FinderFileRevealer(fileAccessManager: manager) { revealedURLs = $0 }

        try revealer.reveal(Track(url: url))

        #expect(revealedURLs == [url])
        #expect(backend.startedURLs == [url])
        #expect(backend.stoppedURLs.isEmpty)
    }

    @Test func missingFilesAreNotRevealedAndTheirScopeIsReleased() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let root = try fixture.folder("Album")
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)
        var revealed = false
        let revealer = FinderFileRevealer(fileAccessManager: manager) { _ in revealed = true }
        let track = Track(
            url: root.appendingPathComponent("missing.mp3"),
            location: .insideFolder(sourceID: source.id, relativePath: "missing.mp3")
        )

        #expect(throws: CocoaError.self) { try revealer.reveal(track) }

        #expect(!revealed)
        #expect(backend.stoppedURLs == [root])
    }

    @Test func unknownSourcesDoNotFallBackToAnExistingOriginalURL() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("song.mp3")
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: Library(), backend: backend)
        var revealed = false
        let revealer = FinderFileRevealer(fileAccessManager: manager) { _ in revealed = true }
        let track = Track(url: url, location: .selectedFile(sourceID: UUID()))

        #expect(throws: FileAccessError.self) { try revealer.reveal(track) }

        #expect(!revealed)
        #expect(backend.startedURLs.isEmpty)
    }

    @Test func failedBookmarkResolutionDoesNotActivateAccessOrRevealTheOriginalURL() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: url))
        library.updateSource(source)
        backend.failsResolution = true
        let manager = FileAccessManager(library: library, backend: backend)
        var revealed = false
        let revealer = FinderFileRevealer(fileAccessManager: manager) { _ in revealed = true }
        let track = Track(url: url, location: .selectedFile(sourceID: source.id))

        #expect(throws: TestFileAccessBackend.Failure.self) { try revealer.reveal(track) }

        #expect(!revealed)
        #expect(backend.startedURLs.isEmpty)
        #expect(backend.stoppedURLs.isEmpty)
    }

    @Test func revealingDoesNotReleaseAnotherReadersActiveScope() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: url))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)
        let location = FileLocation.selectedFile(sourceID: source.id)
        let reader = try manager.acquire(location)
        defer { reader.close() }
        var revealedURLs: [URL] = []
        let revealer = FinderFileRevealer(fileAccessManager: manager) { revealedURLs = $0 }

        try revealer.reveal(Track(url: url, location: location))

        #expect(revealedURLs == [url])
        #expect(backend.startedURLs == [url])
        #expect(backend.stoppedURLs.isEmpty)
        reader.close()
        #expect(backend.stoppedURLs == [url])
    }
}
#endif

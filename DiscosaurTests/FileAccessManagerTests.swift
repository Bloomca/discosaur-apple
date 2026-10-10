import Foundation
import Testing
@testable import Discosaur

@MainActor
struct FileAccessManagerTests {
    @Test func preparingSourcesDistinguishesFilesAndFoldersWithoutCommittingThem() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let folderURL = try fixture.folder("Album")
        let fileURL = try fixture.file("song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)

        let folder = try manager.prepareSource(for: folderURL)
        let file = try manager.prepareSource(for: fileURL)
        #expect(folder.source.kind == .folder)
        #expect(file.source.kind == .file)
        #expect(folder.access.resourceURL == folderURL)
        #expect(file.access.resourceURL == fileURL)
        #expect(library.sources.isEmpty)
        #expect(backend.stoppedURLs.isEmpty)

        folder.access.close()
        file.access.close()
        #expect(backend.startedURLs == [folderURL, fileURL])
        #expect(backend.stoppedURLs == [folderURL, fileURL])
    }

    @Test func repeatedSelectionsReuseBothStagedAndCommittedSourceIdentity() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = try fixture.file("song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)

        let first = try manager.prepareSource(for: fileURL)
        let second = try manager.prepareSource(for: fileURL)
        #expect(second.source.id == first.source.id)
        library.updateSource(second.source)
        first.access.close()
        second.access.close()

        let third = try manager.prepareSource(for: fileURL)
        #expect(third.source.id == first.source.id)
        third.access.close()
        #expect(library.sources.count == 1)
        #expect(backend.startedURLs.count == backend.stoppedURLs.count)
    }

    @Test func folderChildrenShareOneRootScopeAndCloseIsIdempotent() throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        let first = try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "Disc 1/01.mp3"))
        let second = try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "Disc 2/01.mp3"))
        #expect(first.resourceURL == root.appendingPathComponent("Disc 1/01.mp3"))
        #expect(second.resourceURL == root.appendingPathComponent("Disc 2/01.mp3"))
        #expect(backend.startedURLs == [root])

        first.close()
        first.close()
        #expect(backend.stoppedURLs.isEmpty)
        second.close()
        second.close()
        #expect(backend.stoppedURLs == [root])

        let next = try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "03.mp3"))
        next.close()
        #expect(backend.startedURLs == [root, root])
        #expect(backend.stoppedURLs == [root, root])
    }

    @Test func selectedFileUsesTheResolvedBookmarkURL() throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/Moved/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        let access = try manager.acquire(.selectedFile(sourceID: source.id))
        #expect(access.resourceURL == fileURL)
        #expect(backend.startedURLs == [fileURL])
        access.close()
        #expect(backend.stoppedURLs == [fileURL])
    }

    @Test func staleBookmarksAreRefreshedWithoutChangingSourceIdentity() throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Moved Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root, isStale: true))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        let access = try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "song.mp3"))
        let refreshed = try #require(library.source(id: source.id))
        #expect(refreshed.id == source.id)
        #expect(refreshed.kind == source.kind)
        #expect(refreshed.bookmarkData != source.bookmarkData)
        #expect(backend.bookmarkedURLs == [root])
        #expect(try backend.resolveBookmark(refreshed.bookmarkData).isStale == false)
        #expect(access.resourceURL == root.appendingPathComponent("song.mp3"))
        access.close()
        #expect(backend.stoppedURLs == [root])
    }

    @Test func failedStaleBookmarkRefreshReleasesAccessAndPreservesTheSource() {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root, isStale: true))
        library.updateSource(source)
        backend.failsBookmarkCreation = true
        let manager = FileAccessManager(library: library, backend: backend)

        #expect(throws: TestFileAccessBackend.Failure.self) {
            try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "song.mp3"))
        }
        #expect(library.sources == [source])
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs == [root])
    }

    @Test(arguments: ["", "..", "../song.mp3", "/song.mp3", "Disc/../song.mp3", "Disc//song.mp3", "."])
    func invalidRelativePathsReleaseTheirScope(path: String) {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        #expect(throws: FileAccessError.self) {
            try manager.acquire(.insideFolder(sourceID: source.id, relativePath: path))
        }
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs == [root])
    }

    @Test func symlinkEscapesAreRejected() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let root = try fixture.folder("Album")
        let outside = try fixture.folder("Outside")
        _ = try fixture.file("Outside/song.mp3")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Link"),
            withDestinationURL: outside
        )
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        #expect(throws: FileAccessError.self) {
            try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "Link/song.mp3"))
        }
        #expect(FileLocation.relativePath(of: root.appendingPathComponent("Link/song.mp3"), inside: root) == nil)
        #expect(backend.stoppedURLs == [root])
    }

    @Test func siblingPathPrefixesAreNotInsideTheFolder() {
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/Music/Album Other/song.mp3")
        #expect(FileLocation.relativePath(of: sibling, inside: root) == nil)
        #expect(FileLocation.relativePath(of: root, inside: root) == nil)
    }

    @Test func fileAndFolderLocationsCannotBeInterchanged() {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/song.mp3")
        let folderURL = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let file = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        let folder = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: folderURL))
        library.updateSource(file)
        library.updateSource(folder)
        let manager = FileAccessManager(library: library, backend: backend)

        #expect(throws: FileAccessError.self) {
            try manager.acquire(.insideFolder(sourceID: file.id, relativePath: "song.mp3"))
        }
        #expect(throws: FileAccessError.self) {
            try manager.acquire(.selectedFile(sourceID: folder.id))
        }
        #expect(backend.startedURLs == [fileURL, folderURL])
        #expect(backend.stoppedURLs == [fileURL, folderURL])
    }

    @Test func unknownOrUnresolvableSourcesDoNotActivateAccess() {
        let library = Library()
        let backend = TestFileAccessBackend()
        let manager = FileAccessManager(library: library, backend: backend)
        #expect(throws: FileAccessError.self) {
            try manager.acquire(.selectedFile(sourceID: UUID()))
        }

        let source = FileSource(kind: .file, bookmarkData: Data())
        library.updateSource(source)
        #expect(throws: TestFileAccessBackend.Failure.self) {
            try manager.acquire(.selectedFile(sourceID: source.id))
        }
        #expect(backend.startedURLs.isEmpty)
        #expect(backend.stoppedURLs.isEmpty)
    }

    @Test func resourcesNeedingNoScopeAreNotStopped() throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        backend.startsSucceed = false
        let fileURL = URL(fileURLWithPath: "/App/Container/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        let access = try manager.acquire(.selectedFile(sourceID: source.id))
        let local = try manager.acquireLocalFile(at: fileURL)
        access.close()
        local.close()
        #expect(backend.startedURLs == [fileURL, fileURL])
        #expect(backend.stoppedURLs.isEmpty)
    }

    @Test func droppingTheLastHandleReleasesAccess() throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)

        var access: ScopedFileAccess? = try manager.acquire(.selectedFile(sourceID: source.id))
        #expect(access != nil)
        access = nil
        #expect(backend.stoppedURLs == [fileURL])
    }

    @Test func failedSourcePreparationBalancesTheSelectedGrant() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = try fixture.file("song.mp3")
        let library = Library()
        let backend = TestFileAccessBackend()
        backend.failsBookmarkCreation = true
        let manager = FileAccessManager(library: library, backend: backend)

        #expect(throws: TestFileAccessBackend.Failure.self) {
            try manager.prepareSource(for: fileURL)
        }
        #expect(library.sources.isEmpty)
        #expect(backend.startedURLs == [fileURL])
        #expect(backend.stoppedURLs == [fileURL])
    }

    @Test func systemFolderBookmarksResolveAndReadNestedFiles() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let root = try fixture.folder("Album")
        let fileURL = try fixture.file("Album/Disc 1/01 - Song #1.flac")
        let contents = Data([1, 2, 3])
        try contents.write(to: fileURL)
        let library = Library()
        let manager = FileAccessManager(library: library)
        let selection = try manager.prepareSource(for: root)
        library.updateSource(selection.source)
        selection.access.close()

        let access = try manager.acquire(.insideFolder(
            sourceID: selection.source.id,
            relativePath: "Disc 1/01 - Song #1.flac"
        ))
        defer { access.close() }
        #expect(selection.source.kind == .folder)
        #expect(access.resourceURL.resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath())
        #expect(try Data(contentsOf: access.resourceURL) == contents)
    }

    @Test func systemBookmarksRoundTripForASelectedFile() throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = try fixture.file("song.mp3")
        let library = Library()
        let manager = FileAccessManager(library: library)
        let selection = try manager.prepareSource(for: fileURL)
        library.updateSource(selection.source)
        selection.access.close()

        let access = try manager.acquire(.selectedFile(sourceID: selection.source.id))
        defer { access.close() }
        #expect(!selection.source.bookmarkData.isEmpty)
        #expect(access.resourceURL.resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath())
    }
}

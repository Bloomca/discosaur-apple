import Foundation
import Testing
@testable import Discosaur

@MainActor
struct AlbumArtworkCacheTests {
    @Test func loadingOnePlaylistDoesNotReadArtworkFromTheRestOfTheLibrary() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Collection", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let cover = FileLocation.insideFolder(sourceID: source.id, relativePath: "Album/cover.jpg")
        let selected = Playlist(tracks: [track(cover: cover), track(cover: cover)])
        let other = Playlist(tracks: [track(cover: .insideFolder(sourceID: source.id, relativePath: "Other/cover.jpg"))])
        library.updatePlaylist(selected)
        library.updatePlaylist(other)
        let reader = RecordingArtworkReader()
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend), reader: reader)

        #expect(await reader.readURLs.isEmpty)
        await cache.load(for: selected)
        await cache.load(for: selected)

        #expect(await reader.readURLs == [root.appendingPathComponent("Album/cover.jpg")])
        #expect(cache.data(for: cover) == Data([1, 2, 3]))
        #expect(cache.data(for: other.tracks.first?.album?.coverLocation) == nil)
        #expect(library.playlists == [selected, other])
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs == [root])
    }

    @Test func artworkUsesTheMovedBookmarkAndPersistsItsRefreshInTheLibrary() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Moved Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root, isStale: true))
        library.updateSource(source)
        let cover = FileLocation.insideFolder(sourceID: source.id, relativePath: "cover.jpg")
        let reader = RecordingArtworkReader()
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend), reader: reader)

        await cache.load(cover)

        #expect(await reader.readURLs == [root.appendingPathComponent("cover.jpg")])
        #expect(cache.data(for: cover) != nil)
        #expect(library.source(id: source.id)?.bookmarkData != source.bookmarkData)
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs == [root])
    }

    @Test func concurrentBrowsingAndPlayerRequestsShareOneReadAndKeepTheScopeOpen() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let cover = FileLocation.insideFolder(sourceID: source.id, relativePath: "cover.jpg")
        let reader = SuspendedArtworkReader()
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend), reader: reader)
        let first = Task { await cache.load(cover) }
        await reader.waitUntilReading()

        let second = Task {
            await cache.load(cover)
            #expect(cache.data(for: cover) == Data([1, 2, 3]))
        }
        await Task.yield()
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs.isEmpty)
        first.cancel()
        await reader.resume()
        await first.value
        await second.value

        #expect(await reader.readURLs == [root.appendingPathComponent("cover.jpg")])
        #expect(cache.data(for: cover) == Data([1, 2, 3]))
        #expect(backend.stoppedURLs == [root])
    }

    @Test func cancelledPlaylistLoadsStopSchedulingAdditionalArtwork() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let firstCover = FileLocation.insideFolder(sourceID: source.id, relativePath: "first.jpg")
        let secondCover = FileLocation.insideFolder(sourceID: source.id, relativePath: "second.jpg")
        let reader = SuspendedArtworkReader()
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend), reader: reader)
        let playlist = Playlist(tracks: [track(cover: firstCover), track(cover: secondCover)])
        let task = Task { await cache.load(for: playlist) }
        await reader.waitUntilReading()

        task.cancel()
        await reader.resume()
        await task.value

        #expect(await reader.readURLs == [root.appendingPathComponent("first.jpg")])
        #expect(cache.data(for: secondCover) == nil)
        #expect(backend.stoppedURLs == [root])
    }

    @Test func unavailableArtworkCanBeRetriedAndDoesNotKeepItsScopeOpen() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let url = URL(fileURLWithPath: "/Music/Album/cover.jpg")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: url))
        library.updateSource(source)
        let cover = FileLocation.selectedFile(sourceID: source.id)
        let reader = RecordingArtworkReader()
        await reader.setFailsReading(true)
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend), reader: reader)

        await cache.load(cover)
        #expect(cache.data(for: cover) == nil)
        #expect(backend.stoppedURLs == [url])
        await reader.setFailsReading(false)
        await cache.load(cover)

        #expect(cache.data(for: cover) != nil)
        #expect(await reader.readURLs == [url, url])
        #expect(backend.stoppedURLs == [url, url])
    }

    @Test func unknownSourcesAndInvalidPathsDoNotReadArtwork() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let reader = RecordingArtworkReader()
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend), reader: reader)

        await cache.load(.selectedFile(sourceID: UUID()))
        await cache.load(.insideFolder(sourceID: source.id, relativePath: "../cover.jpg"))
        await cache.load(nil)

        #expect(await reader.readURLs.isEmpty)
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs == [root])
    }

    @Test func systemReaderValidatesImagesAndMissingArtworkIsOptional() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let root = try fixture.folder("Album")
        let imageURL = try fixture.file("Album/cover.jpg")
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j/0YAAAAASUVORK5CYII="))
        try imageData.write(to: imageURL)
        _ = try fixture.file("Album/invalid.jpg")
        let library = Library()
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: library, backend: backend))
        let cover = FileLocation.insideFolder(sourceID: source.id, relativePath: "cover.jpg")
        let invalid = FileLocation.insideFolder(sourceID: source.id, relativePath: "invalid.jpg")
        let missing = FileLocation.insideFolder(sourceID: source.id, relativePath: "missing.jpg")

        await cache.load(cover)
        await cache.load(invalid)
        await cache.load(missing)

        #expect(cache.data(for: cover) == imageData)
        #expect(cache.data(for: invalid) == nil)
        #expect(cache.data(for: missing) == nil)
        #expect(backend.startedURLs.count == 3)
        #expect(backend.stoppedURLs.count == 3)
    }

    private func track(cover: FileLocation) -> Track {
        Track(
            url: URL(fileURLWithPath: "/Music/\(UUID().uuidString).mp3"),
            metadata: TrackMetadata(),
            album: Album(title: "Album", artist: "Artist", year: nil, coverLocation: cover)
        )
    }
}

private actor RecordingArtworkReader: AlbumArtworkReading {
    enum Failure: Error { case read }
    private(set) var readURLs: [URL] = []
    private var failsReading = false

    func read(at url: URL) async throws -> Data? {
        readURLs.append(url)
        if failsReading { throw Failure.read }
        return Data([1, 2, 3])
    }

    func setFailsReading(_ fails: Bool) {
        failsReading = fails
    }
}

private actor SuspendedArtworkReader: AlbumArtworkReading {
    private(set) var readURLs: [URL] = []
    private var readContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func read(at url: URL) async throws -> Data? {
        readURLs.append(url)
        await withCheckedContinuation { continuation in
            readContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
        return Data([1, 2, 3])
    }

    func waitUntilReading() async {
        guard readContinuation == nil else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resume() {
        readContinuation?.resume()
        readContinuation = nil
    }
}

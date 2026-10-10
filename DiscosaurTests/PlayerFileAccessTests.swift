import Foundation
import Testing
@testable import Discosaur

@MainActor
struct PlayerFileAccessTests {
    @Test func folderScopeStaysAliveWhilePausedAndTheFileClosesBeforeTheScope() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Moved Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)
        let engine = FileAccessPlaybackEngine()
        let player = Player(engine: engine, fileAccessManager: manager)
        defer { player.stop() }
        let track = Track(
            url: URL(fileURLWithPath: "/Music/Old Album/Disc 1/song.mp3"),
            location: .insideFolder(sourceID: source.id, relativePath: "Disc 1/song.mp3")
        )
        player.selectTrack(in: Playlist(tracks: [track]), at: 0)

        try await player.play()
        #expect(engine.loadedURLs == [root.appendingPathComponent("Disc 1/song.mp3")])
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs.isEmpty)
        #expect(player.currentTrack == track)
        #expect(player.canSeek)
        player.pause()
        #expect(player.status == .paused)
        #expect(backend.stoppedURLs.isEmpty)

        engine.onFileClose = {
            #expect(backend.stoppedURLs.isEmpty)
        }
        player.stop()
        #expect(engine.loadedFileURL == nil)
        #expect(backend.stoppedURLs == [root])
    }

    @Test func stoppingPlaybackDoesNotReleaseAnotherReaderUsingTheSameSource() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let root = URL(fileURLWithPath: "/Music/Album", isDirectory: true)
        let source = FileSource(kind: .folder, bookmarkData: backend.registerBookmark(for: root))
        library.updateSource(source)
        let manager = FileAccessManager(library: library, backend: backend)
        let reader = try manager.acquire(.insideFolder(sourceID: source.id, relativePath: "other.mp3"))
        defer { reader.close() }
        let player = Player(engine: FileAccessPlaybackEngine(), fileAccessManager: manager)
        defer { player.stop() }
        player.selectTrack(in: Playlist(tracks: [Track(
            url: root.appendingPathComponent("song.mp3"),
            location: .insideFolder(sourceID: source.id, relativePath: "song.mp3")
        )]), at: 0)

        try await player.play()
        player.stop()
        #expect(backend.startedURLs == [root])
        #expect(backend.stoppedURLs.isEmpty)
        reader.close()
        #expect(backend.stoppedURLs == [root])
    }

    @Test func selectedFilePlaybackUsesTheResolvedFileRatherThanTheOldTrackURL() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/New/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let engine = FileAccessPlaybackEngine()
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        let track = Track(
            url: URL(fileURLWithPath: "/Music/Old/song.mp3"),
            location: .selectedFile(sourceID: source.id)
        )
        player.selectTrack(in: Playlist(tracks: [track]), at: 0)

        try await player.play()
        #expect(engine.loadedURLs == [fileURL])
        #expect(backend.startedURLs == [fileURL])
        player.stop()
        #expect(backend.stoppedURLs == [fileURL])
    }

    @Test func failedLoadsReleaseAccessAndPublishTheError() async {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let engine = FileAccessPlaybackEngine()
        engine.failsLoading = true
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        player.selectTrack(in: Playlist(tracks: [Track(
            url: fileURL,
            location: .selectedFile(sourceID: source.id)
        )]), at: 0)

        await #expect(throws: FileAccessPlaybackEngine.Failure.self) {
            try await player.play()
        }
        #expect(backend.startedURLs == [fileURL])
        #expect(backend.stoppedURLs == [fileURL])
        #expect(player.errorMessage != nil)
        #expect(!player.isLoading)
        #expect(player.status == .stopped)
    }

    @Test func missingSourcesDoNotFallBackToTheUnscopedTrackURL() async {
        let library = Library()
        let backend = TestFileAccessBackend()
        let engine = FileAccessPlaybackEngine()
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        player.selectTrack(in: Playlist(tracks: [Track(
            url: URL(fileURLWithPath: "/Music/song.mp3"),
            location: .selectedFile(sourceID: UUID())
        )]), at: 0)

        await #expect(throws: FileAccessError.self) {
            try await player.play()
        }
        #expect(engine.loadedURLs.isEmpty)
        #expect(backend.startedURLs.isEmpty)
        #expect(player.errorMessage != nil)
    }

    @Test func cancellationDuringLoadingReleasesAccessWithoutAnErrorAlert() async {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let engine = FileAccessPlaybackEngine()
        engine.suspendsLoading = true
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        player.selectTrack(in: Playlist(tracks: [Track(
            url: fileURL,
            location: .selectedFile(sourceID: source.id)
        )]), at: 0)
        let task = Task { try await player.play() }
        await engine.waitUntilLoading()
        #expect(backend.stoppedURLs.isEmpty)

        task.cancel()
        engine.resumeLoading()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(backend.stoppedURLs == [fileURL])
        #expect(player.errorMessage == nil)
        #expect(!player.isLoading)
        #expect(engine.loadedFileURL == nil)
    }

    @Test func changingSelectionDuringLoadingReleasesTheOldScope() async {
        let library = Library()
        let backend = TestFileAccessBackend()
        let fileURL = URL(fileURLWithPath: "/Music/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: fileURL))
        library.updateSource(source)
        let engine = FileAccessPlaybackEngine()
        engine.suspendsLoading = true
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        let first = Track(url: fileURL, location: .selectedFile(sourceID: source.id))
        let second = Track(url: URL(fileURLWithPath: "/App/other.mp3"))
        let playlist = Playlist(tracks: [first, second])
        player.selectTrack(in: playlist, at: 0)
        let task = Task { try await player.play() }
        await engine.waitUntilLoading()

        player.selectTrack(in: playlist, at: 1)
        #expect(backend.stoppedURLs.isEmpty)
        engine.resumeLoading()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(player.currentTrack == second)
        #expect(player.status == .stopped)
        #expect(player.errorMessage == nil)
        #expect(backend.stoppedURLs == [fileURL])
        #expect(engine.loadedFileURL == nil)
    }

    @Test func deletingTheLoadedTrackClosesItsFileBeforeReleasingAccess() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let url = URL(fileURLWithPath: "/Music/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: url))
        library.updateSource(source)
        let engine = FileAccessPlaybackEngine()
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        let track = Track(url: url, location: .selectedFile(sourceID: source.id))
        let playlist = Playlist(tracks: [track])
        library.updatePlaylist(playlist)
        player.selectTrack(in: playlist, at: 0)
        try await player.play()
        engine.onFileClose = { #expect(backend.stoppedURLs.isEmpty) }

        player.updatePlaylist(try #require(library.removeTrack(id: track.id, from: playlist.id)))

        #expect(engine.loadedFileURL == nil)
        #expect(backend.stoppedURLs == [url])
        #expect(library.sources == [source])
        #expect(player.status == .stopped)
    }

    @Test func deletingATrackDuringLoadingPreventsPlaybackAndReleasesAccessAfterTheRead() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let url = URL(fileURLWithPath: "/Music/song.mp3")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: url))
        library.updateSource(source)
        let engine = FileAccessPlaybackEngine()
        engine.suspendsLoading = true
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        let track = Track(url: url, location: .selectedFile(sourceID: source.id))
        let playlist = Playlist(tracks: [track])
        library.updatePlaylist(playlist)
        player.selectTrack(in: playlist, at: 0)
        let task = Task { try await player.play() }
        await engine.waitUntilLoading()

        player.updatePlaylist(try #require(library.removeTrack(id: track.id, from: playlist.id)))
        #expect(backend.stoppedURLs.isEmpty)
        engine.resumeLoading()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(backend.stoppedURLs == [url])
        #expect(engine.loadedFileURL == nil)
        #expect(player.currentTrack == nil)
        #expect(!player.isLoading)
        #expect(player.errorMessage == nil)
    }

    @Test func deletionAdvanceClosesTheOldFileAndScopeBeforeOpeningTheNextSource() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let firstURL = URL(fileURLWithPath: "/Music/first.mp3")
        let nextURL = URL(fileURLWithPath: "/Music/next.mp3")
        let firstSource = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: firstURL))
        let nextSource = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: nextURL))
        library.updateSource(firstSource)
        library.updateSource(nextSource)
        let engine = FileAccessPlaybackEngine()
        let player = Player(engine: engine, fileAccessManager: FileAccessManager(library: library, backend: backend))
        defer { player.stop() }
        let first = Track(url: firstURL, location: .selectedFile(sourceID: firstSource.id))
        let next = Track(url: nextURL, location: .selectedFile(sourceID: nextSource.id))
        let playlist = Playlist(tracks: [first, next])
        library.updatePlaylist(playlist)
        player.selectTrack(in: playlist, at: 0)
        try await player.play()
        var closedFirstFile = false
        engine.onFileClose = { [weak engine] in
            if engine?.loadedFileURL == firstURL {
                #expect(backend.stoppedURLs.isEmpty)
                #expect(backend.startedURLs == [firstURL])
                closedFirstFile = true
            }
        }

        player.updatePlaylist(try #require(library.removeTrack(id: first.id, from: playlist.id)))
        #expect(closedFirstFile)
        #expect(backend.stoppedURLs == [firstURL])
        for _ in 0..<1_000 {
            if player.status == .playing { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(player.status == .playing)
        #expect(player.currentTrack == next)
        #expect(engine.loadedFileURL == nextURL)
        #expect(backend.startedURLs == [firstURL, nextURL])
        #expect(backend.stoppedURLs == [firstURL])
    }
}

@MainActor
private final class FileAccessPlaybackEngine: FilePlaybackEngine {
    enum Failure: Error {
        case load
    }

    var position: TimeInterval = 0
    var volume: Float = 1
    var onPlaybackEnded: (@MainActor () -> Void)?
    var onFileClose: (() -> Void)?
    var failsLoading = false
    var suspendsLoading = false
    private(set) var loadedURLs: [URL] = []
    private(set) var loadedFileURL: URL?
    private var loadID = UUID()
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func loadFile(at url: URL) async throws -> AudioFileInfo {
        let requestID = loadID
        loadedURLs.append(url)
        if suspendsLoading {
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        try Task.checkCancellation()
        guard requestID == loadID else { throw CancellationError() }
        if failsLoading { throw Failure.load }
        loadedFileURL = url
        return AudioFileInfo(duration: 60)
    }

    func waitUntilLoading() async {
        guard loadContinuation == nil else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeLoading() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func play() throws {}
    func pause() {}

    func stop() {
        loadID = UUID()
        if loadedFileURL != nil { onFileClose?() }
        loadedFileURL = nil
    }

    func seek(to position: TimeInterval) throws {
        self.position = position
    }
}

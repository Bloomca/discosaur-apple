import Foundation
import Testing
@testable import Discosaur

@MainActor
struct LibraryPersistenceTests {
    @Test func startupRestoresOnceAndDoesNotAutosaveOrPersistSelection() async throws {
        let first = Playlist(name: "First", tracks: [])
        let second = Playlist(name: "Second", tracks: [])
        let source = FileSource(kind: .file, bookmarkData: Data([1]))
        let snapshot = LibrarySnapshot(playlists: [first, second], sources: [source])
        let storage = TestLibraryStorage(snapshot: snapshot)
        let library = Library()
        library.updatePlaylist(Playlist(name: "Old in-memory contents", tracks: []))
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .zero)

        await persistence.loadIfNeeded()
        #expect(library.selectedPlaylist == first)
        await persistence.loadIfNeeded()
        library.selectPlaylist(id: second.id)
        await persistence.flush()

        #expect(persistence.status == .ready)
        #expect(library.snapshot == snapshot)
        #expect(library.selectedPlaylist == second)
        #expect(await storage.loadCount == 1)
        #expect(await storage.savedSnapshots.isEmpty)
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func concurrentWindowsShareStartupEvenWhenTheFirstViewTaskIsCancelled() async throws {
        let snapshot = LibrarySnapshot(playlists: [Playlist(name: "Restored", tracks: [])])
        let storage = TestLibraryStorage(snapshot: snapshot)
        await storage.suspendNextLoad()
        let library = Library()
        let persistence = LibraryPersistence(library: library, storage: storage)
        let firstWindow = Task { await persistence.loadIfNeeded() }
        await storage.waitUntilLoading()

        #expect(persistence.status == .loading)
        #expect(library.playlists.isEmpty)
        await persistence.loadIfNeeded()
        firstWindow.cancel()
        await storage.resumeLoad()
        await firstWindow.value

        #expect(persistence.status == .ready)
        #expect(library.snapshot == snapshot)
        #expect(await storage.loadCount == 1)
        #expect(await storage.savedSnapshots.isEmpty)
    }

    @Test func burstEditsAutosaveTheFinalSnapshotWithoutAnExplicitSave() async throws {
        let library = Library()
        let storage = TestLibraryStorage()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .milliseconds(10))
        await persistence.loadIfNeeded()
        let playlist = library.createPlaylist()
        for index in 1...10 {
            library.renamePlaylist(id: playlist.id, to: "Rename \(index)")
        }

        try await waitUntil { await storage.savedSnapshots.count == 1 }
        try await Task.sleep(for: .milliseconds(30))

        #expect(await storage.savedSnapshots == [library.snapshot])
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func flushBypassesDebounceAndCapturesSourcesTracksRenamesAndRemoval() async throws {
        let library = Library()
        let storage = TestLibraryStorage()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .seconds(60))
        await persistence.loadIfNeeded()
        let source = FileSource(kind: .file, bookmarkData: Data([1]))
        let track = Track(url: URL(fileURLWithPath: "/Unavailable/song.mp3"), location: .selectedFile(sourceID: source.id))
        library.updateSource(source)
        let playlist = Playlist(name: "Original", tracks: [track])
        library.updatePlaylist(playlist)
        library.renamePlaylist(id: playlist.id, to: "Renamed")
        library.removeTrack(id: track.id, from: playlist.id)

        await persistence.flush()

        #expect(await storage.savedSnapshots == [library.snapshot])
        #expect(library.playlists.first?.name == "Renamed")
        #expect(library.playlists.first?.tracks.isEmpty == true)
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func deletingPlaylistsIsSavedAndRestoredWithoutDeletingBookmarks() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let storage = Storage(fileURL: fileURL)
        let first = Playlist(name: "Deleted", tracks: [])
        let second = Playlist(name: "Kept", tracks: [])
        let source = FileSource(kind: .file, bookmarkData: Data([1]))
        try await storage.save(LibrarySnapshot(playlists: [first, second], sources: [source]))
        let library = Library()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .seconds(60))
        await persistence.loadIfNeeded()

        library.removePlaylist(id: first.id)
        #expect(persistence.hasUnsavedChanges)
        await persistence.flush()
        #expect(try await storage.load() == LibrarySnapshot(playlists: [second], sources: [source]))
        library.removePlaylist(id: UUID())
        #expect(!persistence.hasUnsavedChanges)
        library.removePlaylist(id: second.id)
        await persistence.flush()
        let relaunched = Library()
        await LibraryPersistence(library: relaunched, storage: storage).loadIfNeeded()

        #expect(relaunched.playlists.isEmpty)
        #expect(relaunched.selectedPlaylist == nil)
        #expect(relaunched.sources == [source])
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func unchangedUpdatesAndBrowsingDoNotScheduleWrites() async throws {
        let source = FileSource(kind: .file, bookmarkData: Data([1]))
        let first = Playlist(tracks: [])
        let second = Playlist(tracks: [])
        let storage = TestLibraryStorage(snapshot: LibrarySnapshot(playlists: [first, second], sources: [source]))
        let library = Library()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .zero)
        await persistence.loadIfNeeded()

        library.updateSource(source)
        library.updatePlaylist(first)
        library.renamePlaylist(id: first.id, to: first.name)
        library.renamePlaylist(id: first.id, to: " ")
        library.selectPlaylist(id: second.id)
        await persistence.flush()

        #expect(await storage.savedSnapshots.isEmpty)
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func editsDuringAnInflightSaveAreWrittenAfterItAndFlushesShareOneWriter() async throws {
        let library = Library()
        let storage = TestLibraryStorage()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .seconds(60))
        await persistence.loadIfNeeded()
        await storage.suspendNextSave()
        let playlist = library.createPlaylist()
        let beforeRename = library.snapshot
        let firstFlush = Task { await persistence.flush() }
        await storage.waitUntilSaving()
        library.renamePlaylist(id: playlist.id, to: "Latest edit")
        let secondFlush = Task { await persistence.flush() }
        await Task.yield()
        #expect(await storage.saveCount == 1)
        #expect(persistence.hasUnsavedChanges)

        await storage.resumeSave()
        await firstFlush.value
        await secondFlush.value

        #expect(await storage.savedSnapshots == [beforeRename, library.snapshot])
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func failedWritesRemainDirtyAndCanBeRetriedWithoutAnotherEdit() async throws {
        let library = Library()
        let storage = TestLibraryStorage()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .seconds(60))
        await persistence.loadIfNeeded()
        await storage.setFailsSaving(true)
        library.createPlaylist()

        await persistence.flush()
        #expect(persistence.hasUnsavedChanges)
        #expect(persistence.errorMessage != nil)
        #expect(await storage.savedSnapshots.isEmpty)
        await storage.setFailsSaving(false)
        await persistence.flush()

        #expect(await storage.savedSnapshots == [library.snapshot])
        #expect(persistence.errorMessage == nil)
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func failedLoadCannotOverwriteTheFileAndRetryDoesNotAutosave() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let original = Data("{\"version\":999}".utf8)
        try original.write(to: fileURL)
        let library = Library()
        let previous = library.createPlaylist()
        let storage = Storage(fileURL: fileURL)
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .zero)
        await persistence.loadIfNeeded()

        #expect(persistence.status == .failed)
        #expect(library.playlists == [previous])
        library.createPlaylist() // Even a direct non-UI mutation must not overwrite it.
        await persistence.flush()
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(!persistence.hasUnsavedChanges)
        let repaired = LibrarySnapshot(playlists: [Playlist(name: "Recovered", tracks: [])])
        try await storage.save(repaired)
        let repairedData = try Data(contentsOf: fileURL)
        await persistence.retryLoad()
        await persistence.flush()

        #expect(persistence.status == .ready)
        #expect(persistence.errorMessage == nil)
        #expect(library.snapshot == repaired)
        #expect(try Data(contentsOf: fileURL) == repairedData)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await condition(), "Timed out waiting for autosave")
    }
}

private actor TestLibraryStorage: LibraryStoring {
    enum Failure: Error { case save }
    private let snapshot: LibrarySnapshot?
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var savedSnapshots: [LibrarySnapshot] = []
    private var failsSaving = false
    private var shouldSuspendSave = false
    private var shouldSuspendLoad = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadStartedContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: LibrarySnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() async throws -> LibrarySnapshot? {
        loadCount += 1
        if shouldSuspendLoad {
            shouldSuspendLoad = false
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
                loadStartedContinuation?.resume()
                loadStartedContinuation = nil
            }
        }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        saveCount += 1
        if shouldSuspendSave {
            shouldSuspendSave = false
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        if failsSaving { throw Failure.save }
        savedSnapshots.append(snapshot)
    }

    func suspendNextLoad() {
        shouldSuspendLoad = true
    }

    func waitUntilLoading() async {
        guard loadContinuation == nil else { return }
        await withCheckedContinuation { loadStartedContinuation = $0 }
    }

    func resumeLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func setFailsSaving(_ fails: Bool) {
        failsSaving = fails
    }

    func suspendNextSave() {
        shouldSuspendSave = true
    }

    func waitUntilSaving() async {
        guard saveContinuation == nil else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

import Foundation
import Testing
@testable import Discosaur

@MainActor
struct PlaylistSelectorTests {
    @Test func subsequentSelectionsAppendSortedBatchesAndPreserveIdentity() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("Z existing.mp3")
        let second = try fixture.file("A added 2.mp3")
        let tenth = try fixture.file("A added 10.mp3")
        let library = Library()
        let selector = PlaylistSelector(library: library, metadataReader: SelectionMetadataReader())

        let imported = await selector.selectFiles([existing])
        let original = try #require(library.selectedPlaylist)
        #expect(imported == original)
        library.renamePlaylist(id: original.id, to: "Favourites")
        await selector.selectFiles([tenth, second])

        let playlist = try #require(library.selectedPlaylist)
        #expect(library.playlists == [playlist])
        #expect(playlist.id == original.id)
        #expect(playlist.name == "Favourites")
        #expect(playlist.tracks.map(\.url) == [existing, second, tenth])
        #expect(playlist.tracks.first == original.tracks.first)
        #expect(selector.errorMessage == nil)
        #expect(!selector.isLoading)
    }

    @Test func addingFoldersSkipsExistingFilesAndReadsOnlyNewMetadata() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("Album/existing.mp3")
        let reader = SelectionMetadataReader()
        let library = Library()
        let selector = PlaylistSelector(library: library, metadataReader: reader)
        await selector.selectFiles([existing])
        let original = try #require(library.selectedPlaylist)
        let added = try fixture.file("Album/added.mp3")

        await selector.selectFiles([fixture.directory, existing])

        let playlist = try #require(library.selectedPlaylist)
        #expect(playlist.id == original.id)
        #expect(playlist.tracks.map(\.url) == [existing, added])
        #expect(playlist.tracks.first == original.tracks.first)
        let readURLs = await reader.readURLs
        #expect(readURLs == [existing, added])
    }

    @Test func distinctFilesWithTheSameNameAreBothAdded() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let first = try fixture.file("First/song.mp3")
        let second = try fixture.file("Second/song.mp3")
        let library = Library()
        let selector = PlaylistSelector(library: library, metadataReader: SelectionMetadataReader())

        await selector.selectFiles([first])
        await selector.selectFiles([second])

        #expect(library.selectedPlaylist?.tracks.map(\.url) == [first, second])
    }

    @Test func duplicateAndEmptySelectionsLeaveLibraryUnchanged() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("song.mp3")
        let reader = SelectionMetadataReader()
        let library = Library()
        let selector = PlaylistSelector(library: library, metadataReader: reader)

        #expect(await selector.selectFiles([]) == nil)
        #expect(library.playlists.isEmpty)
        await selector.selectFiles([existing])
        let original = try #require(library.selectedPlaylist)

        #expect(await selector.selectFiles([existing, existing]) == nil)
        #expect(library.playlists == [original])
        #expect(await selector.selectFiles([]) == nil)
        #expect(library.playlists == [original])
        let readURLs = await reader.readURLs
        #expect(readURLs == [existing])
        #expect(!selector.isLoading)
    }

    @Test func failedImportsDoNotDiscardExistingPlaylist() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("existing.mp3")
        let added = try fixture.file("added.mp3")
        let missing = fixture.directory.appendingPathComponent("missing.mp3")
        let library = Library()
        let selector = PlaylistSelector(library: library, metadataReader: SelectionMetadataReader())
        await selector.selectFiles([existing])
        let original = try #require(library.selectedPlaylist)

        #expect(await selector.selectFiles([added, missing]) == nil)

        #expect(library.playlists == [original])
        #expect(library.selectedPlaylist == original)
        #expect(selector.errorMessage != nil)
        #expect(!selector.isLoading)
    }

    @Test func cancelledImportsDoNotDiscardExistingPlaylist() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("existing.mp3")
        let added = try fixture.file("added.mp3")
        let reader = SelectionMetadataReader(cancelledURL: added)
        let library = Library()
        let selector = PlaylistSelector(library: library, metadataReader: reader)
        await selector.selectFiles([existing])
        let original = try #require(library.selectedPlaylist)

        #expect(await selector.selectFiles([added]) == nil)

        #expect(library.playlists == [original])
        #expect(library.selectedPlaylist == original)
        #expect(selector.errorMessage == nil)
        #expect(!selector.isLoading)
    }

    @Test func importsOnlyModifyTheSelectedPlaylist() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let shared = try fixture.file("shared.mp3")
        let first = Playlist(tracks: [Track(url: shared)])
        let second = Playlist(tracks: [])
        let library = Library()
        library.updatePlaylist(first)
        library.updatePlaylist(second)
        library.selectPlaylist(id: second.id)
        let selector = PlaylistSelector(library: library, metadataReader: SelectionMetadataReader())

        let imported = await selector.selectFiles([shared])

        #expect(imported?.id == second.id)
        #expect(library.playlist(id: first.id) == first)
        #expect(library.selectedPlaylist?.id == second.id)
        #expect(library.selectedPlaylist?.tracks.map(\.url) == [shared])
        #expect(library.playlists.count == 2)
    }

    @Test func capturedPickerDestinationIsUsedAfterBrowsingAnotherPlaylist() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let added = try fixture.file("added.mp3")
        let library = Library()
        let destination = library.createPlaylist()
        let browsing = library.createPlaylist()
        let selector = PlaylistSelector(library: library, metadataReader: SelectionMetadataReader())

        let imported = await selector.selectFiles([added], into: destination.id)

        #expect(imported?.id == destination.id)
        #expect(library.playlist(id: destination.id)?.tracks.map(\.url) == [added])
        #expect(library.selectedPlaylist == browsing)
        #expect(library.playlists.count == 2)
    }

    @Test func deletingDestinationWhilePickerIsOpenDoesNotRedirectTheImport() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let added = try fixture.file("added.mp3")
        let library = Library()
        let destination = library.createPlaylist()
        let remaining = library.createPlaylist()
        library.removePlaylist(id: destination.id)
        let reader = SelectionMetadataReader()
        let selector = PlaylistSelector(library: library, metadataReader: reader)

        let imported = await selector.selectFiles([added], into: destination.id)

        #expect(imported == nil)
        #expect(library.playlists == [remaining])
        #expect(library.sources.isEmpty)
        #expect(await reader.readURLs.isEmpty)
        #expect(!selector.isLoading)
        #expect(selector.errorMessage == nil)
    }

    @Test func switchingPlaylistsDuringImportDoesNotRedirectTracks() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let added = try fixture.file("added.mp3")
        let first = Playlist(tracks: [])
        let second = Playlist(tracks: [])
        let library = Library()
        library.updatePlaylist(first)
        library.updatePlaylist(second)
        let reader = SuspendedSelectionMetadataReader()
        let selector = PlaylistSelector(library: library, metadataReader: reader)
        let task = Task { await selector.selectFiles([added]) }
        await reader.waitUntilReading()

        library.selectPlaylist(id: second.id)
        await reader.resume()
        let imported = await task.value

        #expect(imported?.id == first.id)
        #expect(library.playlist(id: first.id)?.tracks.map(\.url) == [added])
        #expect(library.selectedPlaylist == second)
        #expect(library.playlists.count == 2)
    }

    @Test(arguments: [false, true])
    func deletingTheImportDestinationDoesNotRecreateItOrRedirectTracks(hasAnotherPlaylist: Bool) async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let added = try fixture.file("added.mp3")
        let library = Library()
        let original = library.createPlaylist()
        let other = hasAnotherPlaylist ? library.createPlaylist() : nil
        library.selectPlaylist(id: original.id)
        let reader = SuspendedSelectionMetadataReader()
        let selector = PlaylistSelector(library: library, metadataReader: reader)
        let task = Task { await selector.selectFiles([added]) }
        await reader.waitUntilReading()

        library.removePlaylist(id: original.id)
        await reader.resume()
        let imported = await task.value

        #expect(imported == nil)
        #expect(library.playlists == other.map { [$0] } ?? [])
        #expect(library.selectedPlaylist == other)
        #expect(library.sources.isEmpty)
        #expect(selector.errorMessage == nil)
        #expect(!selector.isLoading)
    }

    @Test func editsDuringImportArePreserved() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let added = try fixture.file("added.mp3")
        let other = try fixture.file("other.mp3")
        let original = Playlist(tracks: [])
        let library = Library()
        library.updatePlaylist(original)
        let reader = SuspendedSelectionMetadataReader()
        let selector = PlaylistSelector(library: library, metadataReader: reader)
        let task = Task { await selector.selectFiles([added]) }
        await reader.waitUntilReading()

        library.updatePlaylist(Playlist(id: original.id, name: "Renamed during import", tracks: [Track(url: other)]))
        await reader.resume()
        let imported = await task.value

        #expect(imported?.id == original.id)
        #expect(imported?.name == "Renamed during import")
        #expect(library.selectedPlaylist?.id == original.id)
        #expect(library.selectedPlaylist?.tracks.map(\.url) == [other, added])
    }

    @Test func overlappingFirstImportsShareOnePlaylistAndDoNotDuplicateTracks() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let shared = try fixture.file("shared.mp3")
        let library = Library()
        let reader = SuspendedSelectionMetadataReader()
        let firstSelector = PlaylistSelector(library: library, metadataReader: reader)
        let secondSelector = PlaylistSelector(library: library, metadataReader: SelectionMetadataReader())
        let task = Task { await firstSelector.selectFiles([shared]) }
        await reader.waitUntilReading()

        let imported = await secondSelector.selectFiles([shared])
        await reader.resume()
        let duplicateImport = await task.value

        #expect(imported != nil)
        #expect(duplicateImport == nil)
        #expect(library.playlists.count == 1)
        #expect(library.selectedPlaylist?.tracks.map(\.url) == [shared])
    }

    @Test func creatingAPlaylistDuringImportDoesNotRedirectTracksOrSelection() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let added = try fixture.file("added.mp3")
        let library = Library()
        let original = library.createPlaylist()
        let reader = SuspendedSelectionMetadataReader()
        let selector = PlaylistSelector(library: library, metadataReader: reader)
        let task = Task { await selector.selectFiles([added]) }
        await reader.waitUntilReading()

        let created = library.createPlaylist()
        library.renamePlaylist(id: original.id, to: "Original destination")
        await reader.resume()
        let imported = await task.value

        #expect(imported?.id == original.id)
        #expect(imported?.name == "Original destination")
        #expect(library.playlist(id: original.id)?.tracks.map(\.url) == [added])
        #expect(library.selectedPlaylist == created)
        #expect(created.tracks.isEmpty)
        #expect(library.playlists.count == 2)
    }
}

private actor SelectionMetadataReader: TrackMetadataReading {
    private(set) var readURLs: [URL] = []
    private let cancelledURL: URL?

    init(cancelledURL: URL? = nil) {
        self.cancelledURL = cancelledURL
    }

    func read(at url: URL) async throws -> TrackMetadata {
        readURLs.append(url)
        if url == cancelledURL {
            throw CancellationError()
        }
        return TrackMetadata()
    }
}

private actor SuspendedSelectionMetadataReader: TrackMetadataReading {
    private var readContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func read(at url: URL) async throws -> TrackMetadata {
        await withCheckedContinuation { continuation in
            readContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
        return TrackMetadata()
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

private struct PlaylistSelectionFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaylistSelectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ relativePath: String) throws -> URL {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Metadata is supplied by a test reader; audio decoding is not needed here.
        try Data().write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

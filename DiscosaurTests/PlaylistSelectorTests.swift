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
        let selector = PlaylistSelector(metadataReader: SelectionMetadataReader())

        await selector.selectFiles([existing])
        let original = try #require(selector.playlist)
        await selector.selectFiles([tenth, second])

        let playlist = try #require(selector.playlist)
        #expect(playlist.id == original.id)
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
        let selector = PlaylistSelector(metadataReader: reader)
        await selector.selectFiles([existing])
        let original = try #require(selector.playlist)
        let added = try fixture.file("Album/added.mp3")

        await selector.selectFiles([fixture.directory, existing])

        let playlist = try #require(selector.playlist)
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
        let selector = PlaylistSelector(metadataReader: SelectionMetadataReader())

        await selector.selectFiles([first])
        await selector.selectFiles([second])

        #expect(selector.playlist?.tracks.map(\.url) == [first, second])
    }

    @Test func duplicateAndEmptySelectionsLeavePlaylistUnchanged() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("song.mp3")
        let reader = SelectionMetadataReader()
        let selector = PlaylistSelector(metadataReader: reader)
        await selector.selectFiles([existing])
        let original = try #require(selector.playlist)

        await selector.selectFiles([existing, existing])
        #expect(selector.playlist == original)
        await selector.selectFiles([])
        #expect(selector.playlist == original)
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
        let selector = PlaylistSelector(metadataReader: SelectionMetadataReader())
        await selector.selectFiles([existing])
        let original = try #require(selector.playlist)

        await selector.selectFiles([added, missing])

        #expect(selector.playlist == original)
        #expect(selector.errorMessage != nil)
        #expect(!selector.isLoading)
    }

    @Test func cancelledImportsDoNotDiscardExistingPlaylist() async throws {
        let fixture = try PlaylistSelectionFixture()
        defer { fixture.remove() }
        let existing = try fixture.file("existing.mp3")
        let added = try fixture.file("added.mp3")
        let reader = SelectionMetadataReader(cancelledURL: added)
        let selector = PlaylistSelector(metadataReader: reader)
        await selector.selectFiles([existing])
        let original = try #require(selector.playlist)

        await selector.selectFiles([added])

        #expect(selector.playlist == original)
        #expect(selector.errorMessage == nil)
        #expect(!selector.isLoading)
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

import Foundation
import Testing
@testable import Discosaur

struct TrackScannerTests {
    @Test(arguments: [
        "aac", "aif", "aiff", "aifc", "caf", "flac", "m4a", "m4b",
        "mp3", "oga", "ogg", "opus", "wav", "wave", "FLAC", "MP3",
    ])
    func recognizesAudioExtensions(_ fileExtension: String) async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }
        let url = try fixture.file("song.\(fileExtension)")

        let tracks = try await TrackScanner().tracks(from: [url])

        #expect(tracks == [Track(url: url)])
    }

    @Test func filtersNonAudioAndSortsFilenamesNaturally() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }
        let urls = try ["Track 10.mp3", "cover.png", "Track 2.MP3", "notes.txt"].map {
            try fixture.file($0)
        }

        let tracks = try await TrackScanner().tracks(from: urls)

        #expect(tracks.map(\.name) == ["Track 2.MP3", "Track 10.mp3"])
    }

    @Test func scansFoldersRecursivelyAndSkipsHiddenItems() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }
        _ = try fixture.file("album/disc/02.flac")
        _ = try fixture.file("01.mp3")
        _ = try fixture.file("album/cover.png")
        _ = try fixture.file(".hidden.mp3")
        _ = try fixture.file(".hidden/03.mp3")
        _ = try fixture.file("Player.app/04.mp3")

        let tracks = try await TrackScanner().tracks(from: [fixture.directory])

        #expect(tracks.map(\.name) == ["01.mp3", "02.flac"])
    }

    @Test func deduplicatesOverlappingFilesAndFolders() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }
        let url = try fixture.file("album/song.mp3")
        let album = fixture.directory.appendingPathComponent("album", isDirectory: true)

        let tracks = try await TrackScanner().tracks(from: [fixture.directory, url, album, url])

        #expect(tracks == [Track(url: url)])
    }

    @Test func keepsDistinctFilesWithTheSameName() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }
        let first = try fixture.file("Disc 1/song.mp3")
        let second = try fixture.file("Disc 2/song.mp3")

        let tracks = try await TrackScanner().tracks(from: [fixture.directory])

        #expect(tracks == [Track(url: first), Track(url: second)])
        #expect(tracks[0].id != tracks[1].id)
    }

    @Test func emptyFolderProducesNoTracks() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }

        let tracks = try await TrackScanner().tracks(from: [fixture.directory])

        #expect(tracks.isEmpty)
    }

    @Test func missingSelectionThrows() async throws {
        let fixture = try SelectionFixture()
        defer { fixture.remove() }
        let missingURL = fixture.directory.appendingPathComponent("missing.mp3")

        await #expect(throws: (any Error).self) {
            try await TrackScanner().tracks(from: [missingURL])
        }
    }
}

private struct SelectionFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscosaurTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ relativePath: String) throws -> URL {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // These tests exercise selection, not audio decoding.
        try Data().write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

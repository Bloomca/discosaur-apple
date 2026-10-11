import Foundation
import Testing
@testable import Discosaur

struct StorageTests {
    @Test func missingFileIsFirstLaunchAndDoesNotCreateAnEmptyDocument() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("Application Support/Discosaur/library.json")
        let storage = Storage(fileURL: fileURL)

        #expect(try await storage.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func completeLibraryRoundTripsWithoutOpeningAnyMediaOrBookmarks() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("Application Support/Discosaur/library.json")
        let snapshot = sampleSnapshot()
        try await Storage(fileURL: fileURL).save(snapshot)

        // A new storage instance simulates relaunch. These media paths do not exist,
        // and the opaque test bookmarks cannot resolve, but all entries must survive.
        #expect(try await Storage(fileURL: fileURL).load() == snapshot)
    }

    @Test func documentIsVersionedJSONWithReferencesNotArtworkOrUIState() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let snapshot = sampleSnapshot()
        try await Storage(fileURL: fileURL).save(snapshot)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])

        #expect(Set(json.keys) == ["version", "sources", "playlists"])
        #expect(json["version"] as? Int == 1)
        let sources = try #require(json["sources"] as? [[String: Any]])
        #expect(sources.first?["kind"] as? String == "folder")
        #expect(sources.first?["bookmarkData"] as? String == snapshot.sources.first?.bookmarkData.base64EncodedString())
        let playlists = try #require(json["playlists"] as? [[String: Any]])
        let tracks = try #require(playlists.first?["tracks"] as? [[String: Any]])
        let album = try #require(tracks.first?["album"] as? [String: Any])
        #expect(album["coverLocation"] != nil)
        #expect(album["coverData"] == nil)
        #expect(album["bookmarkData"] == nil)
    }

    @Test func replacingADocumentKeepsLatestContentsIncludingEmptyPlaylists() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let storage = Storage(fileURL: fileURL)
        try await storage.save(sampleSnapshot())
        let empty = LibrarySnapshot(playlists: [Playlist(name: "Emptied", tracks: [])])

        try await storage.save(empty)

        #expect(try await storage.load() == empty)
    }

    @Test(arguments: ["", "not JSON", "{}", "{\"version\":1,\"sources\":[]}"])
    func malformedDocumentsAreNotTreatedAsFirstLaunchOrChanged(json: String) async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let original = Data(json.utf8)
        try original.write(to: fileURL)

        await #expect(throws: DecodingError.self) {
            try await Storage(fileURL: fileURL).load()
        }
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test(arguments: [0, 2, 999])
    func unsupportedVersionsAreRejectedBeforeDecodingThePayload(version: Int) async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let original = Data("{\"version\":\(version),\"futurePayload\":true}".utf8)
        try original.write(to: fileURL)

        await #expect(throws: StorageError.unsupportedVersion(version)) {
            try await Storage(fileURL: fileURL).load()
        }
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test func invalidRelationshipsCannotLoadOrReplaceAnExistingDocument() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let storage = Storage(fileURL: fileURL)
        let valid = sampleSnapshot()
        let fileSource = FileSource(kind: .file, bookmarkData: Data([1]))
        let folderSource = FileSource(kind: .folder, bookmarkData: Data([2]))
        let missingSourceTrack = Track(url: URL(fileURLWithPath: "/Missing/song.mp3"), location: .selectedFile(sourceID: UUID()))
        let badPathTrack = Track(url: URL(fileURLWithPath: "/Missing/song.mp3"), location: .insideFolder(sourceID: folderSource.id, relativePath: "../song.mp3"))
        let mismatchedTrack = Track(url: URL(fileURLWithPath: "/Missing/song.mp3"), location: .selectedFile(sourceID: folderSource.id))
        let album = Album(title: "Album", artist: nil, year: nil, coverLocation: .selectedFile(sourceID: UUID()))
        let badArtworkTrack = Track(url: URL(fileURLWithPath: "/Missing/song.mp3"), metadata: TrackMetadata(), album: album)
        let duplicate = Playlist(tracks: [])
        let repeatedTrack = Track(url: URL(fileURLWithPath: "/Missing/song.mp3"))
        let invalidSnapshots = [
            LibrarySnapshot(playlists: [duplicate, duplicate]),
            LibrarySnapshot(sources: [fileSource, fileSource]),
            LibrarySnapshot(sources: [FileSource(kind: .file, bookmarkData: Data())]),
            LibrarySnapshot(playlists: [Playlist(tracks: [missingSourceTrack])]),
            LibrarySnapshot(playlists: [Playlist(tracks: [badPathTrack])], sources: [folderSource]),
            LibrarySnapshot(playlists: [Playlist(tracks: [mismatchedTrack])], sources: [folderSource]),
            LibrarySnapshot(playlists: [Playlist(tracks: [badArtworkTrack])]),
            LibrarySnapshot(playlists: [Playlist(tracks: [repeatedTrack, repeatedTrack])]),
            LibrarySnapshot(playlists: [Playlist(tracks: [Track(url: try #require(URL(string: "https://example.com/song.mp3")))])]),
        ]

        for invalid in invalidSnapshots {
            try await storage.save(valid)
            let original = try Data(contentsOf: fileURL)
            await #expect(throws: StorageError.self) { try await storage.save(invalid) }
            #expect(try Data(contentsOf: fileURL) == original)
            // Write a deliberately invalid document, bypassing Storage's save validation.
            try JSONEncoder().encode(LibraryDocumentV1(snapshot: invalid)).write(to: fileURL)
            await #expect(throws: StorageError.self) { try await storage.load() }
        }
    }

    @Test(arguments: ["trackNumber", "discNumber", "duration"])
    func invalidCachedMetadataIsNotSilentlyDropped(field: String) async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let data = try JSONEncoder().encode(LibraryDocumentV1(snapshot: sampleSnapshot()))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var playlists = try #require(json["playlists"] as? [[String: Any]])
        var tracks = try #require(playlists[0]["tracks"] as? [[String: Any]])
        tracks[0][field] = 0
        playlists[0]["tracks"] = tracks
        json["playlists"] = playlists
        try JSONSerialization.data(withJSONObject: json).write(to: fileURL)

        await #expect(throws: StorageError.self) { try await Storage(fileURL: fileURL).load() }
    }

    @Test func aDirectoryAtTheDocumentPathIsAnErrorNotAnEmptyLibrary() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let directory = try fixture.folder("library.json")

        await #expect(throws: (any Error).self) { try await Storage(fileURL: directory).load() }
    }

    @Test func defaultLocationIsLibraryJSONInApplicationSupport() {
        let url = Storage.defaultLibraryURL
        #expect(url.lastPathComponent == "library.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Discosaur")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent() == URL.applicationSupportDirectory)
    }

    @MainActor
    @Test func staleBookmarkRefreshIsAutomaticallyIncludedInTheNextSave() async throws {
        let fixture = try FileAccessFixture()
        defer { fixture.remove() }
        let fileURL = fixture.directory.appendingPathComponent("library.json")
        let mediaURL = try fixture.file("song.mp3")
        let backend = TestFileAccessBackend()
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: mediaURL, isStale: true))
        let location = FileLocation.selectedFile(sourceID: source.id)
        let initial = LibrarySnapshot(playlists: [Playlist(tracks: [Track(url: mediaURL, location: location)])], sources: [source])
        let storage = Storage(fileURL: fileURL)
        try await storage.save(initial)
        let library = Library()
        let persistence = LibraryPersistence(library: library, storage: storage, autosaveDelay: .seconds(60))
        await persistence.loadIfNeeded()

        let access = try FileAccessManager(library: library, backend: backend).acquire(location)
        access.close()
        await persistence.flush()

        #expect(try await storage.load() == library.snapshot)
        #expect(library.sources.first?.bookmarkData != source.bookmarkData)
        #expect(!persistence.hasUnsavedChanges)
    }

    private func sampleSnapshot() -> LibrarySnapshot {
        let folder = FileSource(kind: .folder, bookmarkData: Data([0, 1, 2, 255]))
        let file = FileSource(kind: .file, bookmarkData: Data("opaque bookmark".utf8))
        let album = Album(
            title: "Album", artist: "Album artist", year: 2024,
            coverLocation: .insideFolder(sourceID: folder.id, relativePath: "Album/Cover #1.jpg")
        )
        let first = Track(
            url: URL(fileURLWithPath: "/Unavailable/Album/02 - Song #2.mp3"),
            metadata: TrackMetadata(title: "Song", artist: "Artist", trackNumber: 2, discNumber: 1, duration: 123.5),
            album: album,
            location: .insideFolder(sourceID: folder.id, relativePath: "Album/02 - Song #2.mp3")
        )
        let second = Track(url: URL(fileURLWithPath: "/Unavailable/01.mp3"), location: .selectedFile(sourceID: file.id))
        let legacy = Track(url: URL(fileURLWithPath: "/Unavailable/local.mp3"))
        return LibrarySnapshot(
            playlists: [
                Playlist(name: "Favourites 🎵", tracks: [first, second, legacy]),
                Playlist(name: "Shared", tracks: [first]),
                Playlist(name: "Empty", tracks: []),
            ],
            sources: [folder, file]
        )
    }
}

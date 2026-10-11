import Foundation
import Testing
@testable import Discosaur

@MainActor
struct LibraryStateStorageTests {
    @Test func optionalIDsRoundTripAsOneStringDictionary() throws {
        let fixture = try StateDefaultsFixture()
        defer { fixture.remove() }
        let storage = LibraryStateStorage(defaults: fixture.defaults)
        let state = LibraryState(
            selectedPlaylistID: UUID(), activePlaylistID: UUID(),
            currentTrackID: URL(fileURLWithPath: "/Music/Album/01 - Song #1 🎵.mp3")
        )

        storage.save(state)

        #expect(storage.load() == state)
        let values = try #require(fixture.defaults.dictionary(forKey: LibraryStateStorage.key) as? [String: String])
        #expect(Set(values.keys) == ["selectedPlaylistID", "activePlaylistID", "currentTrackID"])
        #expect(values["selectedPlaylistID"] == state.selectedPlaylistID?.uuidString)
        #expect(values["activePlaylistID"] == state.activePlaylistID?.uuidString)
        #expect(values["currentTrackID"] == state.currentTrackID?.absoluteString)
        #expect(LibraryStateStorage(defaults: try #require(UserDefaults(suiteName: fixture.suiteName))).load() == state)
    }

    @Test func nilValuesReplaceOldReferencesWithoutClearingOtherPreferences() throws {
        let fixture = try StateDefaultsFixture()
        defer { fixture.remove() }
        let storage = LibraryStateStorage(defaults: fixture.defaults)
        fixture.defaults.set("Keep me", forKey: "unrelatedPreference")
        let selectedID = UUID()
        storage.save(LibraryState(selectedPlaylistID: selectedID, activePlaylistID: UUID(), currentTrackID: URL(fileURLWithPath: "/Music/song.mp3")))

        storage.save(LibraryState(selectedPlaylistID: selectedID))

        #expect(storage.load() == LibraryState(selectedPlaylistID: selectedID))
        let values = try #require(fixture.defaults.dictionary(forKey: LibraryStateStorage.key))
        #expect(Set(values.keys) == ["selectedPlaylistID"])
        storage.save(LibraryState())
        #expect(fixture.defaults.object(forKey: LibraryStateStorage.key) == nil)
        #expect(storage.load() == LibraryState())
        #expect(fixture.defaults.string(forKey: "unrelatedPreference") == "Keep me")
    }

    @Test func absentOrMalformedDictionaryIsAnEmptyState() throws {
        let fixture = try StateDefaultsFixture()
        defer { fixture.remove() }
        let storage = LibraryStateStorage(defaults: fixture.defaults)

        #expect(storage.load() == LibraryState())
        fixture.defaults.set("not a dictionary", forKey: LibraryStateStorage.key)
        #expect(storage.load() == LibraryState())
        fixture.defaults.set(["selectedPlaylistID": 42, "activePlaylistID": "not a UUID", "currentTrackID": false], forKey: LibraryStateStorage.key)
        #expect(storage.load() == LibraryState())
    }

    @Test(arguments: ["", "relative/song.mp3", "https://example.com/song.mp3", "not a URL"])
    func nonFileTrackIDsAreIgnoredWithoutDiscardingValidPlaylistIDs(trackID: String) throws {
        let fixture = try StateDefaultsFixture()
        defer { fixture.remove() }
        let selectedID = UUID()
        let activeID = UUID()
        fixture.defaults.set([
            "selectedPlaylistID": selectedID.uuidString,
            "activePlaylistID": activeID.uuidString,
            "currentTrackID": trackID,
        ], forKey: LibraryStateStorage.key)

        #expect(LibraryStateStorage(defaults: fixture.defaults).load() == LibraryState(selectedPlaylistID: selectedID, activePlaylistID: activeID))
    }

    @Test func storedFileURLIsStandardizedLikeTrackIdentity() throws {
        let fixture = try StateDefaultsFixture()
        defer { fixture.remove() }
        let url = URL(fileURLWithPath: "/Music/Album/../song.mp3")
        fixture.defaults.set(["currentTrackID": url.absoluteString], forKey: LibraryStateStorage.key)

        #expect(LibraryStateStorage(defaults: fixture.defaults).load().currentTrackID == Track(url: url).id)
    }

    #if DEBUG
    @Test func testHostUsesIsolatedDefaultsAndLibraryStorage() {
        let url = LibraryStorageLocation.current
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "DiscosaurTests")
        #expect(LibraryStorageLocation.userDefaults !== UserDefaults.standard)
    }
    #endif

    @Test func suitesAreIsolated() throws {
        let first = try StateDefaultsFixture()
        defer { first.remove() }
        let second = try StateDefaultsFixture()
        defer { second.remove() }
        LibraryStateStorage(defaults: first.defaults).save(LibraryState(selectedPlaylistID: UUID()))

        #expect(LibraryStateStorage(defaults: second.defaults).load() == LibraryState())
    }
}

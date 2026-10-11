import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Discosaur

@MainActor
struct LibraryStatePersistenceTests {
    @Test func startupWaitsForJSONThenRestoresIndependentSelectionsWithoutPlaying() async throws {
        let playlists = makePlaylists()
        let snapshot = LibrarySnapshot(playlists: [playlists.playing, playlists.browsing])
        let saved = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[1].id)
        let stateStorage = StateTestStorage(state: saved)
        let jsonStorage = StateTestLibraryStorage(snapshot: snapshot, suspendsLoading: true)
        let library = Library()
        let engine = StateTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let statePersistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        let persistence = LibraryPersistence(library: library, storage: jsonStorage, statePersistence: statePersistence)
        let startup = Task { await persistence.loadIfNeeded() }
        await jsonStorage.waitUntilLoading()

        #expect(persistence.status == .loading)
        #expect(stateStorage.loadCount == 0)
        #expect(stateStorage.savedStates.isEmpty)
        persistence.flushState()
        await persistence.loadIfNeeded() // A second window must not restore early.
        await jsonStorage.resumeLoading()
        await startup.value

        #expect(persistence.status == .ready)
        #expect(library.selectedPlaylist == playlists.browsing)
        #expect(player.activePlaylist == playlists.playing)
        #expect(player.currentTrack == playlists.playing.tracks[1])
        #expect(player.currentIndex == 1)
        #expect(player.status == .stopped)
        #expect(player.position == 0)
        #expect(!player.canSeek)
        #expect(player.canGoPrevious)
        #expect(engine.loadedURLs.isEmpty)
        #expect(engine.playCount == 0)
        #expect(stateStorage.loadCount == 1)
        #expect(stateStorage.savedStates == [saved])
        await persistence.flush()
        #expect(await jsonStorage.savedSnapshots.isEmpty)
    }

    @Test func failedLibraryLoadLeavesDefaultsUntouchedUntilSuccessfulRetry() async throws {
        let playlists = makePlaylists()
        let saved = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[0].id)
        let stateStorage = StateTestStorage(state: saved)
        let jsonStorage = StateTestLibraryStorage(snapshot: LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]), failsLoading: true)
        let library = Library()
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let statePersistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        let persistence = LibraryPersistence(library: library, storage: jsonStorage, statePersistence: statePersistence)

        await persistence.loadIfNeeded()
        persistence.flushState()
        await persistence.flush()
        #expect(persistence.status == .failed)
        #expect(stateStorage.loadCount == 0)
        #expect(stateStorage.savedStates.isEmpty)
        await jsonStorage.setFailsLoading(false)
        await persistence.retryLoad()

        #expect(library.selectedPlaylist == playlists.browsing)
        #expect(player.currentTrack == playlists.playing.tracks[0])
        #expect(stateStorage.savedStates == [saved])
        #expect(await jsonStorage.savedSnapshots.isEmpty)
    }

    @Test(arguments: [false, true])
    func absentOrUnknownBrowsingSelectionFallsBackToFirstPlaylist(unknown: Bool) {
        let playlists = makePlaylists()
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        library.selectPlaylist(id: playlists.browsing.id)
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let stateStorage = StateTestStorage(state: LibraryState(
            selectedPlaylistID: unknown ? UUID() : nil,
            activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[1].id
        ))
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)

        persistence.restoreAndStart()

        #expect(library.selectedPlaylist == playlists.playing)
        #expect(player.currentTrack == playlists.playing.tracks[1])
        #expect(stateStorage.savedStates == [LibraryState(
            selectedPlaylistID: playlists.playing.id, activePlaylistID: playlists.playing.id,
            currentTrackID: playlists.playing.tracks[1].id
        )])
    }

    @Test(arguments: ["missingActive", "missingTrack", "unknownPlaylist", "unknownTrack", "trackInAnotherPlaylist", "emptyPlaylist"])
    func invalidPlaybackPairsAreClearedInsteadOfSelectingADifferentTrack(reason: String) {
        let playlists = makePlaylists()
        let empty = Playlist(tracks: [])
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing, empty]))
        var activeID: UUID? = playlists.playing.id
        var trackID: URL? = playlists.playing.tracks[0].id
        switch reason {
        case "missingActive": activeID = nil
        case "missingTrack": trackID = nil
        case "unknownPlaylist": activeID = UUID()
        case "unknownTrack": trackID = URL(fileURLWithPath: "/Missing/unknown.mp3")
        case "trackInAnotherPlaylist": trackID = playlists.browsing.tracks[0].id
        case "emptyPlaylist": activeID = empty.id
        default: preconditionFailure("Unknown test case")
        }
        let stateStorage = StateTestStorage(state: LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: activeID, currentTrackID: trackID))
        let engine = StateTestEngine()
        let player = Player(engine: engine)
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)

        persistence.restoreAndStart()

        #expect(library.selectedPlaylist == playlists.browsing)
        #expect(player.activePlaylist == nil)
        #expect(player.currentTrack == nil)
        #expect(stateStorage.savedStates == [LibraryState(selectedPlaylistID: playlists.browsing.id)])
        #expect(engine.loadedURLs.isEmpty)
    }

    @Test func repeatedStartupDoesNotResetPlaybackAfterItHasStarted() async throws {
        let playlists = makePlaylists()
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let stateStorage = StateTestStorage(state: LibraryState(activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[0].id))
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        persistence.restoreAndStart()
        try await player.play()
        try player.seek(to: 12)

        persistence.restoreAndStart()

        #expect(player.status == .playing)
        #expect(player.position == 12)
        #expect(stateStorage.loadCount == 1)
        #expect(stateStorage.savedStates.count == 1)
    }

    @Test func restorationResetsPlaybackAndRestoresTheFullQueueNotAlbumNavigation() async throws {
        let otherAlbum = Album(title: "Other", artist: "Artist", year: nil)
        let album = Album(title: "Album", artist: "Artist", year: nil)
        let tracks = [
            Track(url: URL(fileURLWithPath: "/Missing/other.mp3"), metadata: TrackMetadata(), album: otherAlbum),
            Track(url: URL(fileURLWithPath: "/Missing/first.mp3"), metadata: TrackMetadata(), album: album),
            Track(url: URL(fileURLWithPath: "/Missing/second.mp3"), metadata: TrackMetadata(), album: album),
        ]
        let playlist = Playlist(tracks: tracks)
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlist]))
        let engine = StateTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        player.selectAlbum(in: playlist, id: try #require(playlist.albumGroups.first { $0.title == "Album" }).id)
        try await player.play()
        try player.seek(to: 12)
        #expect(!player.canGoPrevious)
        let loadedURLs = engine.loadedURLs
        let playCount = engine.playCount
        let saved = LibraryState(selectedPlaylistID: playlist.id, activePlaylistID: playlist.id, currentTrackID: tracks[1].id)
        let stateStorage = StateTestStorage(state: saved)
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)

        persistence.restoreAndStart()

        #expect(player.status == .stopped)
        #expect(player.position == 0)
        #expect(player.currentTrack == tracks[1])
        #expect(player.canGoPrevious)
        #expect(engine.loadedURLs == loadedURLs)
        #expect(engine.playCount == playCount)
        #expect(stateStorage.savedStates == [saved])
    }

    @Test func browsingSavesAutomaticallyWithoutWritingLibraryJSON() async throws {
        let playlists = makePlaylists()
        let library = Library()
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let stateStorage = StateTestStorage()
        let jsonStorage = StateTestLibraryStorage(snapshot: LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let statePersistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        let persistence = LibraryPersistence(library: library, storage: jsonStorage, statePersistence: statePersistence)
        await persistence.loadIfNeeded()

        library.selectPlaylist(id: playlists.browsing.id)
        try await waitUntil { stateStorage.savedStates.last?.selectedPlaylistID == playlists.browsing.id }
        await persistence.flush()

        #expect(stateStorage.savedStates == [
            LibraryState(selectedPlaylistID: playlists.playing.id),
            LibraryState(selectedPlaylistID: playlists.browsing.id),
        ])
        #expect(await jsonStorage.savedSnapshots.isEmpty)
        #expect(!persistence.hasUnsavedChanges)
    }

    @Test func nextPreviousAutomaticAdvanceAndQueueEndSaveTheCurrentTrack() async throws {
        let playlists = makePlaylists()
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let engine = StateTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let first = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[0].id)
        let second = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[1].id)
        let stateStorage = StateTestStorage(state: first)
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        persistence.restoreAndStart()
        try await player.play()

        engine.onPlaybackEnded?()
        try await waitUntil { player.status == .playing && stateStorage.savedStates.last == second }
        try await player.previous()
        try await waitUntil { stateStorage.savedStates.last == first }
        try await player.next()
        try await waitUntil { stateStorage.savedStates.last == second }
        engine.onPlaybackEnded?()
        let stopped = LibraryState(selectedPlaylistID: playlists.browsing.id)
        try await waitUntil { stateStorage.savedStates.last == stopped }
        persistence.flush()

        #expect(stateStorage.savedStates == [first, second, first, second, stopped])
        #expect(player.activePlaylist == nil)
        #expect(player.currentTrack == nil)
    }

    @Test func pauseSeekVolumeAndMetadataUpdatesDoNotWriteUnchangedIDs() async throws {
        let playlists = makePlaylists()
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let saved = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[0].id)
        let stateStorage = StateTestStorage(state: saved)
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        persistence.restoreAndStart()
        try await player.play()
        try player.seek(to: 12)
        player.pause()
        player.volume = 0.5
        player.isMuted = true
        library.renamePlaylist(id: playlists.playing.id, to: "Renamed")
        player.updatePlaylist(try #require(library.playlist(id: playlists.playing.id)))
        library.selectPlaylist(id: playlists.browsing.id)
        try await Task.sleep(for: .milliseconds(10))
        persistence.flush()
        #expect(stateStorage.savedStates == [saved])

        // Observation must rearm even when the preceding edit did not change IDs.
        try await player.next()
        try await waitUntil { stateStorage.savedStates.last?.currentTrackID == playlists.playing.tracks[1].id }
        persistence.flush()
        #expect(stateStorage.savedStates.count == 2)
    }

    @Test func selectingASharedTrackInAnotherPlaylistRemembersItsNewQueue() async throws {
        let track = Track(url: URL(fileURLWithPath: "/Missing/shared.mp3"))
        let first = Playlist(tracks: [track])
        let second = Playlist(tracks: [track])
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [first, second]))
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let stateStorage = StateTestStorage(state: LibraryState(selectedPlaylistID: first.id, activePlaylistID: first.id, currentTrackID: track.id))
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        persistence.restoreAndStart()

        player.selectTrack(in: second, at: 0)
        let expected = LibraryState(selectedPlaylistID: first.id, activePlaylistID: second.id, currentTrackID: track.id)
        try await waitUntil { stateStorage.savedStates.last == expected }
        persistence.flush()

        #expect(stateStorage.savedStates.count == 2)
    }

    @Test(arguments: [false, true])
    func removingTheCurrentTrackSavesTheSuccessorOrClearsPlayback(paused: Bool) async throws {
        let playlists = makePlaylists()
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let initial = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[0].id)
        let stateStorage = StateTestStorage(state: initial)
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        persistence.restoreAndStart()
        try await player.play()
        if paused { player.pause() }

        player.updatePlaylist(try #require(library.removeTrack(id: playlists.playing.tracks[0].id, from: playlists.playing.id)))
        let expected = paused ? LibraryState(selectedPlaylistID: playlists.browsing.id) : LibraryState(
            selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id,
            currentTrackID: playlists.playing.tracks[1].id
        )
        try await waitUntil { stateStorage.savedStates.last == expected }
        persistence.flush()

        #expect(stateStorage.savedStates == [initial, expected])
    }

    @Test func deletingPlaylistsClearsTheirReferencesAndStopClearsPlaybackImmediately() async throws {
        let playlists = makePlaylists()
        let library = Library()
        library.restore(LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let initial = LibraryState(selectedPlaylistID: playlists.browsing.id, activePlaylistID: playlists.playing.id, currentTrackID: playlists.playing.tracks[0].id)
        let stateStorage = StateTestStorage(state: initial)
        let persistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        persistence.restoreAndStart()

        player.stop()
        persistence.flush() // Quit can happen before the deferred observation callback.
        #expect(stateStorage.savedStates.last == LibraryState(selectedPlaylistID: playlists.browsing.id))
        player.selectTrack(in: playlists.playing, at: 0)
        persistence.flush()
        library.removePlaylist(id: playlists.browsing.id)
        try await waitUntil { stateStorage.savedStates.last?.selectedPlaylistID == playlists.playing.id }
        library.removePlaylist(id: playlists.playing.id)
        player.removePlaylist(id: playlists.playing.id)
        try await waitUntil { stateStorage.savedStates.last == LibraryState() }
        persistence.flush()

        #expect(stateStorage.savedStates.last == LibraryState())
    }

    @Test func defaultsRestoreAcrossInstancesWhileJSONRemainsUnchanged() async throws {
        let defaults = try StateDefaultsFixture()
        defer { defaults.remove() }
        let files = try FileAccessFixture()
        defer { files.remove() }
        let playlists = makePlaylists()
        let snapshot = LibrarySnapshot(playlists: [playlists.playing, playlists.browsing])
        let storage = Storage(fileURL: files.directory.appendingPathComponent("library.json"))
        try await storage.save(snapshot)
        let originalJSON = try Data(contentsOf: storage.fileURL)
        let library = Library()
        let player = Player(engine: StateTestEngine())
        defer { player.stop() }
        let statePersistence = LibraryStatePersistence(library: library, player: player, storage: LibraryStateStorage(defaults: defaults.defaults))
        let persistence = LibraryPersistence(library: library, storage: storage, statePersistence: statePersistence)
        await persistence.loadIfNeeded()
        library.selectPlaylist(id: playlists.browsing.id)
        player.selectTrack(in: playlists.playing, at: 1)
        persistence.flushState()

        let relaunchedLibrary = Library()
        let engine = StateTestEngine()
        let relaunchedPlayer = Player(engine: engine)
        defer { relaunchedPlayer.stop() }
        let relaunchedState = LibraryStatePersistence(library: relaunchedLibrary, player: relaunchedPlayer, storage: LibraryStateStorage(defaults: try #require(UserDefaults(suiteName: defaults.suiteName))))
        let relaunched = LibraryPersistence(library: relaunchedLibrary, storage: storage, statePersistence: relaunchedState)
        await relaunched.loadIfNeeded()

        #expect(relaunchedLibrary.selectedPlaylist == playlists.browsing)
        #expect(relaunchedPlayer.activePlaylist == playlists.playing)
        #expect(relaunchedPlayer.currentTrack == playlists.playing.tracks[1])
        #expect(relaunchedPlayer.status == .stopped)
        #expect(engine.loadedURLs.isEmpty)
        #expect(try Data(contentsOf: storage.fileURL) == originalJSON)
    }

    @Test(arguments: [false, true])
    func emptyLibraryClearsStaleOrMalformedDefaults(staleIDs: Bool) throws {
        let defaults = try StateDefaultsFixture()
        defer { defaults.remove() }
        let storage = LibraryStateStorage(defaults: defaults.defaults)
        if staleIDs {
            storage.save(LibraryState(selectedPlaylistID: UUID(), activePlaylistID: UUID(), currentTrackID: URL(fileURLWithPath: "/Missing/song.mp3")))
        } else {
            defaults.defaults.set("malformed", forKey: LibraryStateStorage.key)
        }
        let library = Library()
        let player = Player(engine: StateTestEngine())
        let persistence = LibraryStatePersistence(library: library, player: player, storage: storage)

        persistence.restoreAndStart()

        #expect(defaults.defaults.object(forKey: LibraryStateStorage.key) == nil)
        #expect(library.selectedPlaylist == nil)
        #expect(player.currentTrack == nil)
    }

    #if os(macOS)
    @Test func quittingWithOnlyASelectionChangeFlushesDefaultsBeforeReturning() async throws {
        let playlists = makePlaylists()
        let library = Library()
        let player = Player(engine: StateTestEngine())
        let stateStorage = StateTestStorage()
        let jsonStorage = StateTestLibraryStorage(snapshot: LibrarySnapshot(playlists: [playlists.playing, playlists.browsing]))
        let statePersistence = LibraryStatePersistence(library: library, player: player, storage: stateStorage)
        let persistence = LibraryPersistence(library: library, storage: jsonStorage, statePersistence: statePersistence)
        await persistence.loadIfNeeded()
        let lifecycle = AppLifecycle()
        lifecycle.persistence = persistence

        library.selectPlaylist(id: playlists.browsing.id)
        #expect(!persistence.hasUnsavedChanges)
        // Calling the delegate directly only asks for a reply; it does not quit the test host.
        #expect(lifecycle.applicationShouldTerminate(.shared) == .terminateNow)

        #expect(stateStorage.savedStates.last == LibraryState(selectedPlaylistID: playlists.browsing.id))
        #expect(await jsonStorage.savedSnapshots.isEmpty)
    }
    #endif

    private func makePlaylists() -> (playing: Playlist, browsing: Playlist) {
        (
            Playlist(name: "Playing", tracks: [
                Track(url: URL(fileURLWithPath: "/Missing/first.mp3")),
                Track(url: URL(fileURLWithPath: "/Missing/second.mp3")),
            ]),
            Playlist(name: "Browsing", tracks: [Track(url: URL(fileURLWithPath: "/Missing/other.mp3"))])
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), "Timed out waiting for state persistence")
    }
}

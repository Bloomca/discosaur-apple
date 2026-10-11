#if os(iOS)
import Foundation
import MediaPlayer
import Testing
@testable import Discosaur

@MainActor
@Suite(.serialized)
struct NowPlayingCoordinatorTests {
    @Test func restoredSelectionDoesNotClaimNowPlayingBeforePlaybackStarts() async throws {
        let fixture = NowPlayingFixture()
        defer { fixture.stop() }
        #expect(fixture.system.state == nil)
        #expect(fixture.system.startCount == 1)
        #expect(await fixture.system.send(.play) == false)
        #expect(fixture.engine.playCount == 0)

        try await fixture.player.play()
        try await waitUntil { fixture.system.state?.playbackRate == 1 }
        #expect(fixture.system.state?.track.name == "First track")
        #expect(fixture.system.state?.duration == 60)
        #expect(fixture.system.state?.commands.previous == false)
        #expect(fixture.system.state?.commands.next == true)
        #expect(fixture.system.state?.commands.seek == true)
    }

    @Test func pauseAndRemoteSeekingPublishAccurateTimeWithoutResuming() async throws {
        let fixture = NowPlayingFixture()
        defer { fixture.stop() }
        try await fixture.player.play()
        try await waitUntil { fixture.system.state?.playbackRate == 1 }
        fixture.player.pause()
        try await waitUntil { fixture.system.state?.playbackRate == 0 }

        #expect(await fixture.system.send(.seek(25)))
        #expect(fixture.system.state?.elapsedTime == 25)
        #expect(fixture.system.state?.playbackRate == 0)
        #expect(fixture.player.status == .paused)
        #expect(await fixture.system.send(.seek(.nan)) == false)
        #expect(await fixture.system.send(.previous) == false)
        #expect(await fixture.system.send(.play))
        #expect(fixture.system.state?.playbackRate == 1)
        #expect(await fixture.system.send(.togglePlayPause))
        #expect(fixture.system.state?.playbackRate == 0)
    }

    @Test func remoteNavigationUsesThePlayingQueueAndStopClearsMetadata() async throws {
        let fixture = NowPlayingFixture()
        defer { fixture.stop() }
        try await fixture.player.play()
        try await waitUntil { fixture.system.state?.playbackRate == 1 }
        #expect(await fixture.system.send(.next))
        #expect(fixture.system.state?.track.id == fixture.playlist.tracks[1].id)
        #expect(fixture.system.state?.commands.next == false)
        #expect(fixture.system.state?.commands.previous == true)
        #expect(await fixture.system.send(.next) == false)
        #expect(await fixture.system.send(.previous))
        #expect(fixture.system.state?.track.id == fixture.playlist.tracks[0].id)

        fixture.player.stop()
        try await waitUntil { fixture.system.state == nil }
        #expect(await fixture.system.send(.play) == false)
    }

    @Test func uiTicksDoNotRepublishButBackgroundRefreshSamplesActualAudioTime() async throws {
        let fixture = NowPlayingFixture()
        defer { fixture.stop() }
        try await fixture.player.play()
        try await waitUntil { fixture.system.state?.playbackRate == 1 }
        let count = fixture.system.updateCount
        fixture.engine.position = 7
        try await Task.sleep(for: .milliseconds(130))
        #expect(fixture.player.position == 7)
        #expect(fixture.system.updateCount == count)

        fixture.player.setProgressUpdatesEnabled(false)
        fixture.engine.position = 37
        fixture.coordinator.refresh()
        #expect(fixture.system.state?.elapsedTime == 37)
        #expect(fixture.system.state?.playbackRate == 1)
        #expect(fixture.player.status == .playing)
    }

    @Test func stoppingTheCoordinatorRemovesCommandsAndDoesNotRearmObservation() async throws {
        let fixture = NowPlayingFixture()
        defer { fixture.stop() }
        try await fixture.player.play()
        try await waitUntil { fixture.system.state?.playbackRate == 1 }
        fixture.coordinator.stop()
        let count = fixture.system.updateCount
        fixture.player.pause()
        try await Task.sleep(for: .milliseconds(10))
        #expect(fixture.system.state == nil)
        #expect(fixture.system.stopCount == 1)
        #expect(fixture.system.updateCount == count)
        #expect(await fixture.system.send(.play) == false)
    }

    @Test func artworkLoadsWithoutAViewAndDoesNotLeakToTheNextTrack() async throws {
        let library = Library()
        let backend = TestFileAccessBackend()
        let coverURL = URL(fileURLWithPath: "/Music/cover.png")
        let source = FileSource(kind: .file, bookmarkData: backend.registerBookmark(for: coverURL))
        library.updateSource(source)
        let cover = FileLocation.selectedFile(sourceID: source.id)
        let album = Album(title: "Album", artist: "Album Artist", year: nil, coverLocation: cover)
        let playlist = Playlist(tracks: [
            Track(url: URL(fileURLWithPath: "/Music/first.mp3"), metadata: TrackMetadata(title: "First"), album: album),
            Track(url: URL(fileURLWithPath: "/Music/second.mp3")),
        ])
        library.updatePlaylist(playlist)
        let manager = FileAccessManager(library: library, backend: backend)
        let reader = NowPlayingArtworkReader()
        let cache = AlbumArtworkCache(fileAccessManager: manager, reader: reader)
        let player = Player(engine: StateTestEngine(), fileAccessManager: manager)
        let system = RecordingNowPlayingSystem()
        let coordinator = NowPlayingCoordinator(player: player, artworkCache: cache, system: system)
        defer { coordinator.stop(); player.stop() }
        player.selectTrack(in: playlist, at: 0)
        try await player.play()
        try await waitUntil { system.state?.artworkData != nil }
        #expect(system.state?.artworkData == Data([1, 2, 3]))
        #expect(await reader.readURLs == [coverURL])
        #expect(backend.stoppedURLs.contains(coverURL))

        #expect(await system.send(.next))
        #expect(system.state?.track.id == playlist.tracks[1].id)
        #expect(system.state?.artworkData == nil)
    }

    @Test func systemDictionaryContainsProgressAndAlbumArtistFallback() {
        let album = Album(title: "Album", artist: "Album Artist", year: nil)
        let track = Track(url: URL(fileURLWithPath: "/Music/song.mp3"), metadata: TrackMetadata(), album: album)
        let system = MediaPlayerNowPlayingSystem()
        defer { system.stop() }
        system.update(NowPlayingState(
            track: track, duration: 60, elapsedTime: 12, playbackRate: 1,
            commands: RemoteCommandAvailability(play: true, pause: true, toggle: true, seek: true), artworkData: nil
        ))
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "song.mp3")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "Album Artist")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "Album")
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? Double == 60)
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 12)
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled)
        system.update(nil)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
        #expect(!MPRemoteCommandCenter.shared().playCommand.isEnabled)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Now Playing state did not update")
    }
}

@MainActor
private struct NowPlayingFixture {
    let engine = StateTestEngine()
    let system = RecordingNowPlayingSystem()
    let playlist = Playlist(tracks: [
        Track(url: URL(fileURLWithPath: "/Music/first.mp3"), metadata: TrackMetadata(title: "First track"), album: nil),
        Track(url: URL(fileURLWithPath: "/Music/second.mp3")),
    ])
    let player: Player
    let coordinator: NowPlayingCoordinator

    init() {
        player = Player(engine: engine)
        player.selectTrack(in: playlist, at: 0)
        let cache = AlbumArtworkCache(fileAccessManager: FileAccessManager(library: Library()))
        coordinator = NowPlayingCoordinator(player: player, artworkCache: cache, system: system)
    }

    func stop() { coordinator.stop(); player.stop() }
}

@MainActor
private final class RecordingNowPlayingSystem: NowPlayingSystem {
    private var handler: (@MainActor @Sendable (RemotePlaybackCommand) async -> Bool)?
    private(set) var state: NowPlayingState?
    private(set) var updateCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(commandHandler: @escaping @MainActor @Sendable (RemotePlaybackCommand) async -> Bool) {
        handler = commandHandler
        startCount += 1
    }
    func update(_ state: NowPlayingState?) { self.state = state; updateCount += 1 }
    func stop() { handler = nil; state = nil; stopCount += 1 }
    func send(_ command: RemotePlaybackCommand) async -> Bool { await handler?(command) ?? false }
}

private actor NowPlayingArtworkReader: AlbumArtworkReading {
    private(set) var readURLs: [URL] = []
    func read(at url: URL) async throws -> Data? {
        readURLs.append(url)
        return Data([1, 2, 3])
    }
}
#endif

import Foundation
import Testing
@testable import Discosaur

@MainActor
struct PlayerPlaylistTests {
    @Test(arguments: [false, true])
    func appendingPreservesCurrentPlaybackAndUpdatesQueue(paused: Bool) async throws {
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let first = Track(url: URL(fileURLWithPath: "/Music/first.mp3"))
        let second = Track(url: URL(fileURLWithPath: "/Music/second.mp3"))
        let original = Playlist(tracks: [first])
        player.selectTrack(in: original, at: 0)
        try await player.play()
        try player.seek(to: 12)
        if paused {
            player.pause()
        }
        let stopCount = engine.stopCount
        let pauseCount = engine.pauseCount
        let updated = Playlist(id: original.id, tracks: [first, second])

        player.updatePlaylist(updated)

        #expect(player.activePlaylist == updated)
        #expect(player.currentIndex == 0)
        #expect(player.currentTrack == first)
        #expect(player.status == (paused ? .paused : .playing))
        #expect(player.position == 12)
        #expect(player.canSeek)
        #expect(player.canGoNext)
        #expect(engine.loadedURLs == [first.url])
        #expect(engine.playCount == 1)
        #expect(engine.stopCount == stopCount)
        #expect(engine.pauseCount == pauseCount)
    }

    @Test func nextCanPlayAnAppendedTrack() async throws {
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let first = Track(url: URL(fileURLWithPath: "/Music/first.mp3"))
        let second = Track(url: URL(fileURLWithPath: "/Music/second.mp3"))
        let original = Playlist(tracks: [first])
        player.selectTrack(in: original, at: 0)
        try await player.play()
        player.updatePlaylist(Playlist(id: original.id, tracks: [first, second]))

        try await player.next()

        #expect(player.activePlaylist?.id == original.id)
        #expect(player.currentTrack == second)
        #expect(player.currentIndex == 1)
        #expect(player.status == .playing)
        #expect(engine.loadedURLs == [first.url, second.url])
        #expect(engine.playCount == 2)
    }

    @Test func updatingAnotherPlaylistLeavesTheActiveQueueUnchanged() {
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let first = Track(url: URL(fileURLWithPath: "/Music/first.mp3"))
        let original = Playlist(tracks: [first])
        player.selectTrack(in: original, at: 0)
        let stopCount = engine.stopCount

        player.updatePlaylist(Playlist(tracks: [first]))

        #expect(player.activePlaylist == original)
        #expect(player.currentTrack == first)
        #expect(player.currentIndex == 0)
        #expect(engine.stopCount == stopCount)
    }
}

@MainActor
private final class PlaylistTestEngine: FilePlaybackEngine {
    var position: TimeInterval = 0
    var volume: Float = 1
    var onPlaybackEnded: (@MainActor () -> Void)?
    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0

    func loadFile(at url: URL) async throws -> AudioFileInfo {
        loadedURLs.append(url)
        return AudioFileInfo(duration: 60)
    }

    func play() throws {
        playCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func stop() {
        stopCount += 1
        position = 0
    }

    func seek(to position: TimeInterval) throws {
        self.position = position
    }
}

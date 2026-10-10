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

    @Test func albumPlaybackStartsAtFirstTrackAndFollowsDiscAndTrackOrder() async throws {
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let discTwo = albumTrack("disc2-track1.mp3", disc: 2, number: 1)
        let trackTwo = albumTrack("disc1-track2.mp3", number: 2)
        let other = albumTrack("other.mp3", title: "Other", number: 1)
        let trackOne = albumTrack("disc1-track1.mp3", number: 1)
        let playlist = Playlist(tracks: [discTwo, trackTwo, other, trackOne])
        let album = try #require(playlist.albumGroups.first { $0.title == "Album" })

        player.selectAlbum(in: playlist, id: album.id)
        try await player.play()

        #expect(player.currentTrack == trackOne)
        #expect(player.currentIndex == 3)
        #expect(!player.canGoPrevious)
        #expect(player.canGoNext)
        try await player.next()
        #expect(player.currentTrack == trackTwo)
        try await player.next()
        #expect(player.currentTrack == discTwo)
        #expect(!player.canGoNext)
        try await player.previous()
        #expect(player.currentTrack == trackTwo)
        try await player.next()
        engine.onPlaybackEnded?()
        #expect(player.currentTrack == nil)
        #expect(player.status == .stopped)
        #expect(!engine.loadedURLs.contains(other.url))
    }

    @Test func selectingATrackReturnsToFullPlaylistNavigationWithoutRestartingIt() async throws {
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let first = albumTrack("first.mp3", number: 1)
        let other = albumTrack("other.mp3", title: "Other", number: 1)
        let second = albumTrack("second.mp3", number: 2)
        let playlist = Playlist(tracks: [first, other, second])
        let album = try #require(playlist.albumGroups.first { $0.title == "Album" })
        player.selectAlbum(in: playlist, id: album.id)
        try await player.play()
        try player.seek(to: 12)
        let stopCount = engine.stopCount

        player.selectTrack(in: playlist, at: 0)

        #expect(player.position == 12)
        #expect(player.status == .playing)
        #expect(engine.stopCount == stopCount)
        try await player.next()
        #expect(player.currentTrack == other)
    }

    @Test func appendingAlbumTracksUpdatesAlbumNavigationWithoutInterruptingPlayback() async throws {
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let other = albumTrack("other.mp3", title: "Other", number: 1)
        let first = albumTrack("first.mp3", number: 1)
        let original = Playlist(tracks: [other, first])
        let album = try #require(original.albumGroups.first { $0.title == "Album" })
        player.selectAlbum(in: original, id: album.id)
        try await player.play()
        try player.seek(to: 12)
        #expect(!player.canGoNext)
        let second = albumTrack("second.mp3", number: 2)
        let anotherOther = albumTrack("other2.mp3", title: "Other", number: 2)
        let updated = Playlist(id: original.id, tracks: [other, first, second, anotherOther])
        let stopCount = engine.stopCount

        player.updatePlaylist(updated)

        #expect(player.currentTrack == first)
        #expect(player.position == 12)
        #expect(player.status == .playing)
        #expect(engine.stopCount == stopCount)
        #expect(player.canGoNext)
        #expect(!player.canGoPrevious)
        try await player.next()
        #expect(player.currentTrack == second)
        #expect(!player.canGoNext)
    }

    @Test(arguments: [false, true])
    func browsingAndCreatingPlaylistsDoNotChangePlaybackOrItsQueue(paused: Bool) async throws {
        let library = Library()
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let first = Track(url: URL(fileURLWithPath: "/Music/first.mp3"))
        let next = Track(url: URL(fileURLWithPath: "/Music/next.mp3"))
        let playing = Playlist(name: "Playing", tracks: [first, next])
        let browsing = Playlist(name: "Browsing", tracks: [Track(url: URL(fileURLWithPath: "/Music/other.mp3"))])
        library.updatePlaylist(playing)
        library.updatePlaylist(browsing)
        player.selectTrack(in: playing, at: 0)
        try await player.play()
        try player.seek(to: 12)
        if paused { player.pause() }
        let stopCount = engine.stopCount
        let pauseCount = engine.pauseCount

        library.selectPlaylist(id: browsing.id)
        #expect(library.selectedPlaylist == browsing)
        #expect(player.activePlaylist == playing)
        let created = library.createPlaylist()
        #expect(library.selectedPlaylist == created)
        #expect(player.activePlaylist == playing)
        #expect(player.currentTrack == first)
        #expect(player.position == 12)
        #expect(player.status == (paused ? .paused : .playing))
        #expect(engine.loadedURLs == [first.url])
        #expect(engine.playCount == 1)
        #expect(engine.stopCount == stopCount)
        #expect(engine.pauseCount == pauseCount)

        try await player.next()
        #expect(player.currentTrack == next)
        #expect(player.activePlaylist == playing)
        #expect(library.selectedPlaylist == created)
        #expect(engine.loadedURLs == [first.url, next.url])
    }

    @Test(arguments: [false, true])
    func renamingThePlayingPlaylistRefreshesItsNameWithoutRestartingPlayback(paused: Bool) async throws {
        let library = Library()
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let track = Track(url: URL(fileURLWithPath: "/Music/song.mp3"))
        let playing = Playlist(name: "Playing", tracks: [track])
        library.updatePlaylist(playing)
        player.selectTrack(in: playing, at: 0)
        try await player.play()
        try player.seek(to: 12)
        let browsing = library.createPlaylist()
        if paused { player.pause() }
        let stopCount = engine.stopCount
        let pauseCount = engine.pauseCount

        library.renamePlaylist(id: playing.id, to: "Renamed")
        player.updatePlaylist(try #require(library.playlist(id: playing.id)))

        #expect(player.activePlaylist?.name == "Renamed")
        #expect(player.currentTrack == track)
        #expect(player.position == 12)
        #expect(player.status == (paused ? .paused : .playing))
        #expect(library.selectedPlaylist == browsing)
        #expect(engine.loadedURLs == [track.url])
        #expect(engine.playCount == 1)
        #expect(engine.stopCount == stopCount)
        #expect(engine.pauseCount == pauseCount)
    }

    @Test(arguments: [false, true])
    func deletingOtherTracksReindexesTheCurrentTrackWithoutInterruptingPlayback(paused: Bool) async throws {
        let library = Library()
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let before = Track(url: URL(fileURLWithPath: "/Music/before.mp3"))
        let current = Track(url: URL(fileURLWithPath: "/Music/current.mp3"))
        let after = Track(url: URL(fileURLWithPath: "/Music/after.mp3"))
        let original = Playlist(name: "Playing", tracks: [before, current, after])
        library.updatePlaylist(original)
        player.selectTrack(in: original, at: 1)
        try await player.play()
        try player.seek(to: 12)
        if paused { player.pause() }
        let stopCount = engine.stopCount
        let pauseCount = engine.pauseCount
        let browsing = library.createPlaylist()

        player.updatePlaylist(try #require(library.removeTrack(id: before.id, from: original.id)))

        #expect(player.currentIndex == 0)
        #expect(player.currentTrack == current)
        #expect(!player.canGoPrevious)
        #expect(player.canGoNext)
        player.updatePlaylist(try #require(library.removeTrack(id: after.id, from: original.id)))
        #expect(player.activePlaylist?.tracks == [current])
        #expect(!player.canGoNext)
        #expect(player.position == 12)
        #expect(player.status == (paused ? .paused : .playing))
        #expect(engine.loadedURLs == [current.url])
        #expect(engine.playCount == 1)
        #expect(engine.stopCount == stopCount)
        #expect(engine.pauseCount == pauseCount)
        #expect(library.selectedPlaylist == browsing)
    }

    @Test(arguments: [false, true])
    func deletingTheCurrentTrackStopsPlaybackWithoutChangingBrowsingSelection(paused: Bool) async throws {
        let library = Library()
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let current = Track(url: URL(fileURLWithPath: "/Music/current.mp3"))
        let other = Track(url: URL(fileURLWithPath: "/Music/other.mp3"))
        let original = Playlist(tracks: [current, other])
        library.updatePlaylist(original)
        player.selectTrack(in: original, at: 0)
        try await player.play()
        try player.seek(to: 12)
        if paused { player.pause() }
        let stopCount = engine.stopCount
        let browsing = library.createPlaylist()

        player.updatePlaylist(try #require(library.removeTrack(id: current.id, from: original.id)))

        #expect(player.status == .stopped)
        #expect(player.currentTrack == nil)
        #expect(player.activePlaylist == nil)
        #expect(player.position == 0)
        #expect(engine.stopCount == stopCount + 1)
        #expect(library.playlist(id: original.id)?.tracks == [other])
        #expect(library.selectedPlaylist == browsing)
    }

    @Test func deletingASharedTrackFromAnotherPlaylistDoesNotStopTheActiveOne() async throws {
        let library = Library()
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let track = Track(url: URL(fileURLWithPath: "/Music/shared.mp3"))
        let playing = Playlist(tracks: [track])
        let browsing = Playlist(tracks: [track])
        library.updatePlaylist(playing)
        library.updatePlaylist(browsing)
        library.selectPlaylist(id: browsing.id)
        player.selectTrack(in: playing, at: 0)
        try await player.play()
        try player.seek(to: 12)
        let stopCount = engine.stopCount

        player.updatePlaylist(try #require(library.removeTrack(id: track.id, from: browsing.id)))

        #expect(library.selectedPlaylist?.tracks.isEmpty == true)
        #expect(library.playlist(id: playing.id) == playing)
        #expect(player.activePlaylist == playing)
        #expect(player.currentTrack == track)
        #expect(player.position == 12)
        #expect(player.status == .playing)
        #expect(engine.stopCount == stopCount)
        #expect(engine.playCount == 1)
    }

    @Test func deletingOtherTracksPreservesAlbumNavigation() async throws {
        let library = Library()
        let engine = PlaylistTestEngine()
        let player = Player(engine: engine)
        defer { player.stop() }
        let other = albumTrack("other.mp3", title: "Other", number: 1)
        let first = albumTrack("first.mp3", number: 1)
        let next = albumTrack("next.mp3", number: 2)
        let original = Playlist(tracks: [other, first, next])
        library.updatePlaylist(original)
        let album = try #require(original.albumGroups.first { $0.title == "Album" })
        player.selectAlbum(in: original, id: album.id)
        try await player.play()
        let stopCount = engine.stopCount

        player.updatePlaylist(try #require(library.removeTrack(id: other.id, from: original.id)))

        #expect(player.currentTrack == first)
        #expect(player.currentIndex == 0)
        #expect(player.canGoNext)
        #expect(!player.canGoPrevious)
        #expect(engine.stopCount == stopCount)
        try await player.next()
        #expect(player.currentTrack == next)
        #expect(!player.canGoNext)
    }

    private func albumTrack(_ filename: String, title: String = "Album", disc: Int = 1, number: Int) -> Track {
        Track(
            url: URL(fileURLWithPath: "/Music/Disc \(disc)/\(filename)"),
            metadata: TrackMetadata(album: title, albumArtist: "Artist", trackNumber: number, discNumber: disc),
            album: Album(title: title, artist: "Artist", year: 2024, coverData: nil)
        )
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

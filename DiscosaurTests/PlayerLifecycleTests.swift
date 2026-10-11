import Foundation
import Testing
@testable import Discosaur

@MainActor
struct PlayerLifecycleTests {
    @Test func interruptionResumesTheSameLoadedTrackOnlyWhenRecommended() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.position = 12

        fixture.engine.onPlaybackEvent?(.interruptionBegan)
        #expect(fixture.player.status == .paused)
        #expect(fixture.player.position == 12)
        #expect(fixture.player.canSeek)
        fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: true))
        try await waitUntil { fixture.player.status == .playing }

        #expect(fixture.engine.playCount == 2)
        #expect(fixture.engine.loadedURLs.count == 1)
        #expect(fixture.player.currentTrack == fixture.playlist.tracks[0])
        #expect(fixture.player.position == 12)
    }

    @Test(arguments: [false, true])
    func pausedOrUnrecommendedPlaybackDoesNotResume(alreadyPaused: Bool) async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        if alreadyPaused { fixture.player.pause() }

        fixture.engine.onPlaybackEvent?(.interruptionBegan)
        fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: alreadyPaused))
        try await Task.sleep(for: .milliseconds(10))

        #expect(fixture.player.status == .paused)
        #expect(fixture.engine.playCount == 1)
    }

    @Test(arguments: [false, true])
    func explicitPauseCancelsRecoveryEvenAfterEndNotification(pauseAfterEnd: Bool) async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.onPlaybackEvent?(.interruptionBegan)
        if pauseAfterEnd { fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: true)) }
        fixture.player.pause()
        if !pauseAfterEnd { fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: true)) }
        try await Task.sleep(for: .milliseconds(10))

        #expect(fixture.player.status == .paused)
        #expect(fixture.engine.playCount == 1)
    }

    @Test(arguments: [false, true])
    func stopOrSelectionChangeCancelsRecovery(stop: Bool) async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.onPlaybackEvent?(.interruptionBegan)
        if stop {
            fixture.player.stop()
        } else {
            fixture.player.selectTrack(in: fixture.playlist, at: 1)
        }
        fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: true))
        try await Task.sleep(for: .milliseconds(10))

        #expect(fixture.player.status == .stopped)
        #expect(fixture.engine.playCount == 1)
        #expect(fixture.player.currentTrack == (stop ? nil : fixture.playlist.tracks[1]))
    }

    @Test func interruptionDuringLoadingCancelsAndCanReloadTheSelectedTrack() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        fixture.engine.suspendsNextLoad = true
        let loading = Task { try await fixture.player.play() }
        try await waitUntil { fixture.engine.isWaitingForLoad }

        fixture.engine.onPlaybackEvent?(.interruptionBegan)
        #expect(!fixture.player.isLoading)
        #expect(fixture.player.status == .stopped)
        fixture.engine.finishLoading()
        do {
            try await loading.value
            Issue.record("Interrupted loading should be cancelled")
        } catch {
            #expect(error is CancellationError)
        }
        fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: true))
        try await waitUntil { fixture.player.status == .playing }
        #expect(fixture.engine.loadedURLs.count == 2)
        #expect(fixture.engine.playCount == 1)
    }

    @Test func headphoneDisconnectionPausesWithoutAutomaticResumption() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.position = 21
        fixture.engine.onPlaybackEvent?(.outputUnavailable)
        fixture.engine.onPlaybackEvent?(.interruptionEnded(shouldResume: true))
        try await Task.sleep(for: .milliseconds(10))

        #expect(fixture.player.status == .paused)
        #expect(fixture.player.position == 21)
        #expect(fixture.engine.playCount == 1)
    }

    @Test func disconnectionDuringAutomaticAdvanceCancelsTheQueuedSuccessor() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.onPlaybackEnded?()
        fixture.engine.onPlaybackEvent?(.outputUnavailable)
        try await Task.sleep(for: .milliseconds(10))

        #expect(fixture.player.status == .stopped)
        #expect(fixture.player.currentTrack == fixture.playlist.tracks[0])
        #expect(fixture.engine.playCount == 1)
    }

    @Test func mediaServicesResetRequiresExplicitPlayAndReloadsAudio() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.onPlaybackEvent?(.mediaServicesReset)

        #expect(fixture.player.status == .stopped)
        #expect(!fixture.player.canSeek)
        #expect(fixture.player.currentTrack == fixture.playlist.tracks[0])
        #expect(fixture.player.position == 0)
        try await fixture.player.play()
        #expect(fixture.engine.loadedURLs.count == 2)
        #expect(fixture.player.status == .playing)
    }

    @Test func backgroundingStopsOnlyUIPollingAndConfigurationRecoveryRebasesTime() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.player.setProgressUpdatesEnabled(false)
        fixture.engine.position = 17
        try await Task.sleep(for: .milliseconds(120))

        #expect(fixture.player.status == .playing)
        #expect(fixture.player.position == 0)
        #expect(fixture.player.currentPlaybackPosition == 17)
        #expect(fixture.engine.pauseCount == 0)
        let revision = fixture.player.timelineRevision
        fixture.engine.onPlaybackEvent?(.configurationChanged)
        #expect(fixture.player.position == 17)
        #expect(fixture.player.timelineRevision > revision)
        fixture.player.setProgressUpdatesEnabled(true)
        #expect(fixture.player.position == 17)
    }

    @Test func navigationKeepsTheSessionUntilTheQueueReallyStops() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        let normalStops = fixture.engine.stopCount
        try await fixture.player.next()
        try await fixture.player.previous()
        #expect(fixture.engine.stopCount == normalStops)
        #expect(fixture.engine.trackChangeStopCount == 2)

        fixture.engine.onPlaybackEnded?()
        try await waitUntil { fixture.player.currentTrack == fixture.playlist.tracks[1] && fixture.player.status == .playing }
        #expect(fixture.engine.stopCount == normalStops)
        fixture.engine.onPlaybackEnded?()
        #expect(fixture.player.currentTrack == nil)
        #expect(fixture.engine.stopCount == normalStops + 1)
    }

    @Test func recoveryFailurePausesAndPublishesTheError() async throws {
        let fixture = LifecycleFixture()
        defer { fixture.player.stop() }
        try await fixture.player.play()
        fixture.engine.onPlaybackEvent?(.failed("Audio output unavailable"))
        #expect(fixture.player.status == .paused)
        #expect(fixture.player.errorMessage == "Audio output unavailable")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Playback state did not update")
    }
}

@MainActor
private struct LifecycleFixture {
    let engine = LifecycleEngine()
    let playlist = Playlist(tracks: [
        Track(url: URL(fileURLWithPath: "/Music/first.mp3")),
        Track(url: URL(fileURLWithPath: "/Music/second.mp3")),
    ])
    let player: Player

    init() {
        player = Player(engine: engine)
        player.selectTrack(in: playlist, at: 0)
    }
}

@MainActor
private final class LifecycleEngine: FilePlaybackEngine {
    var position: TimeInterval = 0
    var volume: Float = 1
    var onPlaybackEnded: (@MainActor () -> Void)?
    var onPlaybackEvent: (@MainActor (PlaybackEngineEvent) -> Void)?
    var suspendsNextLoad = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaitingForLoad: Bool { continuation != nil }
    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var trackChangeStopCount = 0

    func loadFile(at url: URL) async throws -> AudioFileInfo {
        loadedURLs.append(url)
        if suspendsNextLoad {
            suspendsNextLoad = false
            await withCheckedContinuation { continuation = $0 }
        }
        return AudioFileInfo(duration: 60)
    }

    func finishLoading() { continuation?.resume(); continuation = nil }
    func play() throws { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { stopCount += 1; position = 0 }
    func stopForTrackChange() { trackChangeStopCount += 1; position = 0 }
    func seek(to position: TimeInterval) throws { self.position = position }
}

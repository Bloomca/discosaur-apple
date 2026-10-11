#if os(iOS)
import AVFAudio
import Foundation
import Testing
@testable import Discosaur

@MainActor
@Suite(.serialized)
struct AVFilePlaybackLifecycleTests {
    @Test func outputDisconnectionPausesRealAudioAndPreservesSeekPosition() async throws {
        let fixture = try AudioLifecycleFixture()
        defer { fixture.remove() }
        try await fixture.player.play()
        try fixture.player.seek(to: 10)
        fixture.notifications.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
        )
        try await waitUntil { fixture.player.status == .paused }

        #expect(fixture.player.position >= 10)
        #expect(fixture.player.position < 11)
        #expect(fixture.player.canSeek)
        try await fixture.player.play()
        #expect(fixture.player.status == .playing)
        #expect(fixture.player.position >= 10)
    }

    @Test func configurationRecoveryReschedulesRealAudioWithoutRewinding() async throws {
        let fixture = try AudioLifecycleFixture()
        defer { fixture.remove() }
        try await fixture.player.play()
        try fixture.player.seek(to: 10)
        let revision = fixture.player.timelineRevision
        fixture.nativeEngine.stop()
        fixture.notifications.post(name: .AVAudioEngineConfigurationChange, object: fixture.nativeEngine)
        try await waitUntil { fixture.player.timelineRevision > revision }

        #expect(fixture.nativeEngine.isRunning)
        #expect(fixture.player.status == .playing)
        #expect(fixture.player.position >= 10)
        #expect(fixture.player.position < 11)
        #expect(fixture.player.errorMessage == nil)
    }

    @Test func mediaResetRecreatesTheGraphAndPreservesVolumeUntilExplicitPlay() async throws {
        let fixture = try AudioLifecycleFixture()
        defer { fixture.remove() }
        try await fixture.player.play()
        fixture.player.volume = 0.4
        fixture.notifications.post(name: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance())
        try await waitUntil { fixture.player.status == .stopped }

        #expect(fixture.player.currentTrack?.url == fixture.url)
        #expect(!fixture.player.canSeek)
        #expect(fixture.engine.volume == 0.4)
        try await fixture.player.play()
        #expect(fixture.player.status == .playing)
        #expect(fixture.player.canSeek)
        #expect(fixture.player.errorMessage == nil)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Audio lifecycle state did not update")
    }
}

@MainActor
private struct AudioLifecycleFixture {
    let notifications = NotificationCenter()
    let nativeEngine = AVAudioEngine()
    let url: URL
    let engine: AVFilePlaybackEngine
    let player: Player

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("AudioLifecycle-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames: AVAudioFrameCount = 44_100 * 30
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData?[0])
        samples.initialize(repeating: 0, count: Int(frames))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        file.close()
        engine = AVFilePlaybackEngine(notificationCenter: notifications, audioEngine: nativeEngine)
        player = Player(engine: engine)
        player.selectTrack(in: Playlist(tracks: [Track(url: url)]), at: 0)
    }

    func remove() {
        player.stop()
        try? FileManager.default.removeItem(at: url)
    }
}
#endif

import Foundation
import Testing
@testable import Discosaur

@MainActor
struct PlayerVolumeTests {
    @Test func mutingPreservesVolumeAndUnmutingRestoresOutput() {
        let engine = VolumeTestEngine()
        let player = Player(engine: engine)
        player.volume = 0.4

        player.isMuted = true

        #expect(player.volume == 0.4)
        #expect(engine.volume == 0)

        player.isMuted = false

        #expect(player.volume == 0.4)
        #expect(engine.volume == 0.4)
    }

    @Test func changingVolumeWhileMutedKeepsOutputSilentUntilUnmuted() {
        let engine = VolumeTestEngine()
        let player = Player(engine: engine)
        player.isMuted = true

        player.volume = 0.25

        #expect(player.isMuted)
        #expect(player.volume == 0.25)
        #expect(engine.volume == 0)

        player.isMuted = false

        #expect(engine.volume == 0.25)
    }

    @Test func volumeClampsToValidRangeAndIgnoresNonFiniteValues() {
        let engine = VolumeTestEngine()
        let player = Player(engine: engine)

        player.volume = 2
        #expect(player.volume == 1)
        #expect(engine.volume == 1)

        player.volume = -1
        #expect(player.volume == 0)
        #expect(engine.volume == 0)

        player.volume = 0.6
        for invalidValue in [Float.nan, .infinity, -.infinity] {
            player.volume = invalidValue
            #expect(player.volume == 0.6)
            #expect(engine.volume == 0.6)
        }
    }

    @Test func stoppingPreservesVolumeAndMuteSetting() {
        let engine = VolumeTestEngine()
        let player = Player(engine: engine)
        player.volume = 0.5
        player.isMuted = true

        player.stop()

        #expect(player.volume == 0.5)
        #expect(player.isMuted)
        #expect(engine.volume == 0)
    }
}

@MainActor
private final class VolumeTestEngine: FilePlaybackEngine {
    var position: TimeInterval { 0 }
    var volume: Float = 1
    var onPlaybackEnded: (@MainActor () -> Void)?

    func loadFile(at url: URL) async throws -> AudioFileInfo {
        AudioFileInfo(duration: 60)
    }

    func play() throws {}
    func pause() {}
    func stop() {}
    func seek(to position: TimeInterval) throws {}
}

import Foundation

nonisolated struct AudioFileInfo: Equatable, Sendable {
    let duration: TimeInterval
}

nonisolated enum PlaybackEngineEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case outputUnavailable
    case configurationChanged
    case mediaServicesReset
    case failed(String)
}

@MainActor
protocol FilePlaybackEngine: AnyObject {
    var position: TimeInterval { get }

    var volume: Float { get set }

    var onPlaybackEnded: (@MainActor () -> Void)? { get set }
    var onPlaybackEvent: (@MainActor (PlaybackEngineEvent) -> Void)? { get set }

    /// Prepares an accessible local file without starting playback.
    func loadFile(at url: URL) async throws -> AudioFileInfo

    func play() throws
    func pause()

    /// Stops playback, releases the loaded file, and resets position.
    func stop()

    /// Releases the old file without relinquishing the audio session between tracks.
    func stopForTrackChange()

    /// Seeks to a clamped position without resuming paused playback.
    func seek(to position: TimeInterval) throws
}

extension FilePlaybackEngine {
    // Engines without platform audio-session events can use these defaults.
    var onPlaybackEvent: (@MainActor (PlaybackEngineEvent) -> Void)? {
        get { nil }
        set {}
    }

    func stopForTrackChange() { stop() }
}

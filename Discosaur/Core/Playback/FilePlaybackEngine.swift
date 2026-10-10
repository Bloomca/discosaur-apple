import Foundation

nonisolated struct AudioFileInfo: Equatable, Sendable {
    let duration: TimeInterval
}

@MainActor
protocol FilePlaybackEngine: AnyObject {
    var position: TimeInterval { get }

    var volume: Float { get set }

    var onPlaybackEnded: (@MainActor () -> Void)? { get set }

    /// Prepares an accessible local file without starting playback.
    func loadFile(at url: URL) async throws -> AudioFileInfo

    func play() throws
    func pause()

    /// Stops playback, releases the loaded file, and resets position.
    func stop()

    /// Seeks to a clamped position without resuming paused playback.
    func seek(to position: TimeInterval) throws
}

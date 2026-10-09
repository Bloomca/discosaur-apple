import Observation

@MainActor
@Observable
final class Player {
    nonisolated enum Status: Equatable, Sendable {
        case stopped
        case paused
        case playing
    }

    static let shared = Player()

    var currentTrack: Track?
    private(set) var status: Status = .stopped

    private init() {}

    func play() {
        status = .playing
    }

    func pause() {
        status = .paused
    }

    func stop() {
        status = .stopped
        currentTrack = nil
    }
}

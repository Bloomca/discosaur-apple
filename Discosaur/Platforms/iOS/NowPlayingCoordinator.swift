#if os(iOS)
import Foundation
import Observation

@MainActor
final class NowPlayingCoordinator {
    private let player: Player
    private let artworkCache: AlbumArtworkCache
    private let system: any NowPlayingSystem
    private var isRunning = true
    private var hasStartedPlayback = false
    private var artworkLocation: FileLocation?
    private var artworkTask: Task<Void, Never>?
    private var lastObservedState: ObservedState?

    private struct ObservedState: Equatable {
        let track: Track?
        let status: Player.Status
        let duration: TimeInterval?
        let isLoading: Bool
        let canSeek: Bool
        let canGoPrevious: Bool
        let canGoNext: Bool
        let timelineRevision: UInt64
        let artworkData: Data?
    }

    init(player: Player, artworkCache: AlbumArtworkCache, system: (any NowPlayingSystem)? = nil) {
        self.player = player
        self.artworkCache = artworkCache
        self.system = system ?? MediaPlayerNowPlayingSystem()
        self.system.start { [weak self] command in
            guard let self else { return false }
            return await self.handleCommand(command)
        }
        observeAndPublish()
    }

    isolated deinit { stop() }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        artworkTask?.cancel()
        artworkTask = nil
        system.stop()
    }

    // Rebase on foreground/background transitions without changing playback.
    func refresh() {
        guard isRunning else { return }
        publish(observedState)
    }

    func handleCommand(_ command: RemotePlaybackCommand) async -> Bool {
        guard isRunning, hasStartedPlayback, player.currentTrack != nil,
              commandAvailability.accepts(command) else { return false }
        do {
            switch command {
            case .play: try await player.play()
            case .pause: player.pause()
            case .togglePlayPause:
                if player.status == .playing || player.isLoading {
                    player.pause()
                } else {
                    try await player.play()
                }
            case .previous: try await player.previous()
            case .next: try await player.next()
            case .seek(let position): try player.seek(to: position)
            }
            refresh()
            return true
        } catch {
            // Player owns the error displayed in the app; keep system state honest.
            refresh()
            return false
        }
    }

    private var commandAvailability: RemoteCommandAvailability {
        RemoteCommandAvailability(
            play: !player.isLoading,
            pause: true,
            toggle: true,
            previous: !player.isLoading && player.canGoPrevious,
            next: !player.isLoading && player.canGoNext,
            seek: player.canSeek
        )
    }

    private var observedState: ObservedState {
        ObservedState(
            track: player.currentTrack,
            status: player.status,
            duration: player.duration,
            isLoading: player.isLoading,
            canSeek: player.canSeek,
            canGoPrevious: player.canGoPrevious,
            canGoNext: player.canGoNext,
            timelineRevision: player.timelineRevision,
            artworkData: artworkCache.data(for: player.currentTrack?.album?.coverLocation)
        )
    }

    private func observeAndPublish() {
        guard isRunning else { return }
        let state = withObservationTracking {
            observedState
        } onChange: { [weak self] in
            // Observation fires before mutation. Coalesce a completed actor turn
            // so queue transitions do not publish partially updated track state.
            Task { @MainActor [weak self] in self?.observeAndPublish() }
        }
        guard state != lastObservedState else { return }
        lastObservedState = state
        publish(state)
    }

    private func publish(_ state: ObservedState) {
        if state.status == .playing { hasStartedPlayback = true }
        guard hasStartedPlayback, let track = state.track else {
            if state.track == nil { hasStartedPlayback = false }
            artworkTask?.cancel()
            artworkTask = nil
            artworkLocation = nil
            system.update(nil)
            return
        }
        if artworkLocation != track.album?.coverLocation {
            artworkTask?.cancel()
            artworkLocation = track.album?.coverLocation
            let cache = artworkCache
            let location = artworkLocation
            artworkTask = Task { await cache.load(location) }
        }
        let duration = state.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let currentPosition = player.currentPlaybackPosition
        let position = currentPosition.isFinite ? max(0, currentPosition) : 0
        system.update(NowPlayingState(
            track: track,
            duration: duration,
            elapsedTime: min(duration ?? position, position),
            playbackRate: state.status == .playing ? 1 : 0,
            commands: commandAvailability,
            artworkData: state.artworkData
        ))
    }
}
#endif

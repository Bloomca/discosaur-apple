#if os(iOS)
import Foundation
import MediaPlayer
import UIKit
import os

nonisolated enum RemotePlaybackCommand: Equatable, Sendable {
    case play, pause, togglePlayPause, previous, next
    case seek(TimeInterval)
}

nonisolated struct RemoteCommandAvailability: Equatable, Sendable {
    var play = false
    var pause = false
    var toggle = false
    var previous = false
    var next = false
    var seek = false

    func accepts(_ command: RemotePlaybackCommand) -> Bool {
        switch command {
        case .play: play
        case .pause: pause
        case .togglePlayPause: toggle
        case .previous: previous
        case .next: next
        case .seek(let position): seek && position.isFinite
        }
    }
}

nonisolated struct NowPlayingState: Equatable, Sendable {
    let track: Track
    let duration: TimeInterval?
    let elapsedTime: TimeInterval
    let playbackRate: Double
    let commands: RemoteCommandAvailability
    let artworkData: Data?
}

@MainActor
protocol NowPlayingSystem: AnyObject {
    func start(commandHandler: @escaping @MainActor @Sendable (RemotePlaybackCommand) async -> Bool)
    func update(_ state: NowPlayingState?)
    func stop()
}

@MainActor
final class MediaPlayerNowPlayingSystem: NowPlayingSystem {
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let availability = OSAllocatedUnfairLock(initialState: RemoteCommandAvailability())
    private var targets: [(MPRemoteCommand, Any)] = []
    private var commandHandler: (@MainActor @Sendable (RemotePlaybackCommand) async -> Bool)?
    private var artworkData: Data?
    private var artwork: MPMediaItemArtwork?

    func start(commandHandler: @escaping @MainActor @Sendable (RemotePlaybackCommand) async -> Bool) {
        self.commandHandler = commandHandler
        guard targets.isEmpty else { return }
        register(commandCenter.playCommand) { _ in .play }
        register(commandCenter.pauseCommand) { _ in .pause }
        register(commandCenter.togglePlayPauseCommand) { _ in .togglePlayPause }
        register(commandCenter.previousTrackCommand) { _ in .previous }
        register(commandCenter.nextTrackCommand) { _ in .next }
        register(commandCenter.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
            return .seek(event.positionTime)
        }
        commandCenter.stopCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        update(nil)
    }

    func update(_ state: NowPlayingState?) {
        let commands = state?.commands ?? RemoteCommandAvailability()
        availability.withLock { $0 = commands }
        commandCenter.playCommand.isEnabled = commands.play
        commandCenter.pauseCommand.isEnabled = commands.pause
        commandCenter.togglePlayPauseCommand.isEnabled = commands.toggle
        commandCenter.previousTrackCommand.isEnabled = commands.previous
        commandCenter.nextTrackCommand.isEnabled = commands.next
        commandCenter.changePlaybackPositionCommand.isEnabled = commands.seek

        guard let state else {
            infoCenter.nowPlayingInfo = nil
            artworkData = nil
            artwork = nil
            return
        }
        if state.artworkData != artworkData {
            artworkData = state.artworkData
            artwork = state.artworkData.flatMap { UIImage(data: $0) }.map { image in
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.track.name,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        info[MPMediaItemPropertyArtist] = state.track.artist ?? state.track.album?.artist
        info[MPMediaItemPropertyAlbumTitle] = state.track.album?.title
        info[MPMediaItemPropertyPlaybackDuration] = state.duration
        info[MPMediaItemPropertyArtwork] = artwork
        infoCenter.nowPlayingInfo = info
    }

    func stop() {
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        commandHandler = nil
        update(nil)
    }

    isolated deinit { stop() }

    private func register(
        _ command: MPRemoteCommand,
        makeCommand: @escaping @Sendable (MPRemoteCommandEvent) -> RemotePlaybackCommand?
    ) {
        let availability = availability
        let target = command.addTarget { [weak self, availability] event in
            guard let request = makeCommand(event), availability.withLock({ $0.accepts(request) }) else {
                return .commandFailed
            }
            // The callback may arrive off-main. A synchronous success means the
            // available command was accepted; file loading completes asynchronously.
            Task { @MainActor [weak self] in
                guard let handler = self?.commandHandler else { return }
                _ = await handler(request)
            }
            return .success
        }
        targets.append((command, target))
    }
}
#endif

import Foundation
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

    var currentTrack: Track? {
        didSet {
            if currentTrack != oldValue {
                resetPlayback()
            }
        }
    }

    private(set) var status: Status = .stopped
    private(set) var isLoading = false
    private(set) var position: TimeInterval = 0
    private var fileInfo: AudioFileInfo?
    private var volumeValue: Float = 1

    var duration: TimeInterval? { fileInfo?.duration }

    var volume: Float {
        get { volumeValue }
        set {
            guard newValue.isFinite else { return }
            volumeValue = min(1, max(0, newValue))
            engine.volume = volumeValue
        }
    }

    @ObservationIgnored private let engine: any FilePlaybackEngine
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    private init() {
        engine = AVFilePlaybackEngine()
        engine.onPlaybackEnded = { [weak self] in
            guard let self else { return }
            self.stopProgressUpdates()
            self.position = self.duration ?? 0
            self.status = .stopped
            // Keep the finished track loaded so play() can replay it.
        }
    }

    func play() async throws {
        guard let track = currentTrack, !isLoading, status != .playing else { return }
        try Task.checkCancellation()
        let id = requestID

        if loadedURL != track.url {
            try await loadTrack(track)
        }

        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        try engine.play()
        position = engine.position
        status = .playing
        startProgressUpdates()
    }

    func pause() {
        if isLoading {
            // Prevent an in-flight load from starting playback after a pause.
            resetPlayback()
            return
        }
        guard status == .playing else { return }

        engine.pause()
        stopProgressUpdates()
        position = engine.position
        status = .paused
    }

    func stop() {
        if currentTrack == nil {
            resetPlayback()
        } else {
            currentTrack = nil
        }
    }

    func seek(to position: TimeInterval) throws {
        do {
            try engine.seek(to: position)
            self.position = engine.position
        } catch {
            pause()
            throw error
        }
    }

    private func loadTrack(_ track: Track) async throws {
        try Task.checkCancellation()
        guard currentTrack == track else { throw CancellationError() }
        let id = requestID

        isLoading = true
        defer {
            if requestID == id {
                isLoading = false
            }
        }

        // Authorization stays outside the engine and is held while the file is
        // loaded, including while paused. Container files need no scoped grant.
        let hasScopedAccess = track.url.startAccessingSecurityScopedResource()
        var keepsAccess = false
        defer {
            if hasScopedAccess, !keepsAccess {
                track.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let info = try await engine.loadFile(at: track.url)
            try Task.checkCancellation()
            guard requestID == id else { throw CancellationError() }

            fileInfo = info
            loadedURL = track.url
            if hasScopedAccess {
                scopedURL = track.url
                keepsAccess = true
            }
        } catch {
            if requestID == id {
                resetPlayback()
            }
            throw error
        }
    }

    private func resetPlayback() {
        requestID = UUID()
        stopProgressUpdates()
        engine.stop()
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        loadedURL = nil
        fileInfo = nil
        position = 0
        isLoading = false
        status = .stopped
    }

    private func startProgressUpdates() {
        stopProgressUpdates()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.position = self.engine.position

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }
}

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

    private(set) var activePlaylist: Playlist?
    private(set) var currentIndex: Int?

    var currentTrack: Track? {
        guard let activePlaylist, let currentIndex,
              activePlaylist.tracks.indices.contains(currentIndex) else { return nil }
        return activePlaylist.tracks[currentIndex]
    }

    var canGoPrevious: Bool {
        guard currentTrack != nil, let currentIndex else { return false }
        return currentIndex > 0
    }

    var canGoNext: Bool {
        guard currentTrack != nil, let activePlaylist, let currentIndex else { return false }
        return currentIndex < activePlaylist.tracks.count - 1
    }

    private(set) var status: Status = .stopped
    private(set) var isLoading = false
    private(set) var position: TimeInterval = 0
    var errorMessage: String?
    private var fileInfo: AudioFileInfo?
    private var volumeValue: Float = 1

    var duration: TimeInterval? { fileInfo?.duration ?? currentTrack?.duration }

    var canSeek: Bool {
        guard status != .stopped, !isLoading,
              let currentTrack, loadedURL == currentTrack.url,
              let duration = fileInfo?.duration, duration.isFinite, duration > 0 else { return false }
        return true
    }

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
            self?.handlePlaybackEnded()
        }
    }

    func selectTrack(in playlist: Playlist, at index: Int) {
        guard playlist.tracks.indices.contains(index) else { return }
        guard activePlaylist?.id != playlist.id || currentIndex != index else { return }

        resetPlayback()
        if activePlaylist?.id != playlist.id {
            activePlaylist = playlist
        }
        currentIndex = index
    }

    func next() async throws {
        try Task.checkCancellation()
        guard canGoNext, let activePlaylist, let currentIndex else { return }
        selectTrack(in: activePlaylist, at: currentIndex + 1)
        try await play()
    }

    func previous() async throws {
        try Task.checkCancellation()
        guard canGoPrevious, let activePlaylist, let currentIndex else { return }
        selectTrack(in: activePlaylist, at: currentIndex - 1)
        try await play()
    }

    func play() async throws {
        guard let track = currentTrack, !isLoading, status != .playing else { return }
        try Task.checkCancellation()
        errorMessage = nil
        let id = requestID

        if loadedURL != track.url {
            try await loadTrack(track)
        }

        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        do {
            try engine.play()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
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
        resetPlayback()
        currentIndex = nil
        activePlaylist = nil
    }

    func seek(to position: TimeInterval) throws {
        guard canSeek else { return }
        errorMessage = nil
        do {
            try engine.seek(to: position)
            self.position = engine.position
        } catch {
            pause()
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func handlePlaybackEnded() {
        guard status == .playing else { return }
        stopProgressUpdates()
        position = duration ?? 0
        status = .stopped

        guard canGoNext else {
            stop()
            return
        }

        let id = requestID
        Task { @MainActor [weak self] in
            guard let self, self.requestID == id,
                  self.status == .stopped, !self.isLoading else { return }
            // play() publishes failures through errorMessage, including for auto-advance.
            try? await self.next()
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
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
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
        errorMessage = nil
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

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

    private(set) var activePlaylist: Playlist?
    private(set) var currentIndex: Int?
    private var playbackAlbumID: AlbumGroup.ID?
    private var albumTrackIndices: [Int]?

    var currentTrack: Track? {
        guard let activePlaylist, let currentIndex,
              activePlaylist.tracks.indices.contains(currentIndex) else { return nil }
        return activePlaylist.tracks[currentIndex]
    }

    var canGoPrevious: Bool { adjacentTrackIndex(offset: -1) != nil }
    var canGoNext: Bool { adjacentTrackIndex(offset: 1) != nil }

    private func adjacentTrackIndex(offset: Int) -> Int? {
        guard currentTrack != nil, let activePlaylist, let currentIndex else { return nil }
        if let albumTrackIndices {
            guard let position = albumTrackIndices.firstIndex(of: currentIndex),
                  albumTrackIndices.indices.contains(position + offset) else { return nil }
            return albumTrackIndices[position + offset]
        }
        let index = currentIndex + offset
        return activePlaylist.tracks.indices.contains(index) ? index : nil
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

    // Muting silences playback without discarding the chosen volume.
    var isMuted = false {
        didSet {
            engine.volume = isMuted ? 0 : volumeValue
        }
    }

    var volume: Float {
        get { volumeValue }
        set {
            guard newValue.isFinite else { return }
            volumeValue = min(1, max(0, newValue))
            engine.volume = isMuted ? 0 : volumeValue
        }
    }

    @ObservationIgnored private let engine: any FilePlaybackEngine
    @ObservationIgnored private let fileAccessManager: FileAccessManager
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var fileAccess: ScopedFileAccess?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    init(engine: any FilePlaybackEngine, fileAccessManager: FileAccessManager? = nil) {
        self.engine = engine
        self.fileAccessManager = fileAccessManager ?? FileAccessManager(library: Library())
        engine.volume = volumeValue
        engine.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackEnded()
        }
    }

    isolated deinit {
        resetPlayback()
    }

    func selectTrack(in playlist: Playlist, at index: Int) {
        guard playlist.tracks.indices.contains(index) else { return }
        playbackAlbumID = nil
        albumTrackIndices = nil
        selectCurrentTrack(in: playlist, at: index)
    }

    func selectAlbum(in playlist: Playlist, id: AlbumGroup.ID) {
        guard let album = playlist.albumGroups.first(where: { $0.id == id }),
              let firstIndex = album.trackIndices.first else { return }
        playbackAlbumID = album.id
        albumTrackIndices = album.trackIndices
        selectCurrentTrack(in: playlist, at: firstIndex)
    }

    private func selectCurrentTrack(in playlist: Playlist, at index: Int) {
        guard playlist.tracks.indices.contains(index) else { return }
        if activePlaylist?.id == playlist.id, currentTrack?.id == playlist.tracks[index].id {
            activePlaylist = playlist
            currentIndex = index
            return
        }

        resetPlayback()
        activePlaylist = playlist
        currentIndex = index
    }

    // Refresh the queue without resetting the currently loaded track or playback.
    func updatePlaylist(_ playlist: Playlist) {
        guard activePlaylist?.id == playlist.id else { return }
        guard let currentTrack,
              let index = playlist.tracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            stop()
            return
        }

        activePlaylist = playlist
        currentIndex = index
        if let playbackAlbumID {
            let groups = playlist.albumGroups
            let album = groups.first { $0.id == playbackAlbumID && $0.trackIndices.contains(index) }
                ?? groups.first { $0.trackIndices.contains(index) }
            self.playbackAlbumID = album?.id
            albumTrackIndices = album?.trackIndices
        }
    }

    func next() async throws {
        try Task.checkCancellation()
        guard let activePlaylist, let index = adjacentTrackIndex(offset: 1) else { return }
        selectCurrentTrack(in: activePlaylist, at: index)
        try await play()
    }

    func previous() async throws {
        try Task.checkCancellation()
        guard let activePlaylist, let index = adjacentTrackIndex(offset: -1) else { return }
        selectCurrentTrack(in: activePlaylist, at: index)
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
        playbackAlbumID = nil
        albumTrackIndices = nil
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

        // A track inside a selected folder holds that folder's grant
        // so we need to keep it alive
        var access: ScopedFileAccess?
        var keepsAccess = false
        defer {
            if !keepsAccess {
                access?.close()
            }
        }

        do {
            let acquired: ScopedFileAccess
            if let location = track.location {
                acquired = try fileAccessManager.acquire(location)
            } else {
                acquired = try fileAccessManager.acquireLocalFile(at: track.url)
            }
            access = acquired
            let info = try await engine.loadFile(at: acquired.resourceURL)
            try Task.checkCancellation()
            guard requestID == id else { throw CancellationError() }

            fileInfo = info
            loadedURL = track.url
            fileAccess = acquired
            keepsAccess = true
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
        fileAccess?.close()
        fileAccess = nil
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

import AVFAudio
import Foundation

@MainActor
final class AVFilePlaybackEngine: FilePlaybackEngine {
    private var audioEngine: AVAudioEngine
    private var playerNode = AVAudioPlayerNode()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)

    private var file: AVAudioFile?
    private var fileInfo: AudioFileInfo?
    private var frameCount: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var startFrame: AVAudioFramePosition = 0
    private var positionSnapshot: TimeInterval = 0
    private var isPlaying = false
    private var hasScheduledAudio = false
    private var scheduleID = UUID()
    private var loadID = UUID()
    private var playbackStartedAt: TimeInterval?

    #if os(iOS)
    private var isAudioSessionActive = false
    private let notificationCenter: NotificationCenter
    private var notificationObservers: [NSObjectProtocol] = []
    #endif

    var onPlaybackEnded: (@MainActor () -> Void)?
    var onPlaybackEvent: (@MainActor (PlaybackEngineEvent) -> Void)?

    var position: TimeInterval {
        guard let fileInfo else { return 0 }
        guard isPlaying else { return positionSnapshot }
        guard let renderTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: renderTime),
              playerTime.isSampleTimeValid,
              playerTime.sampleRate > 0 else {
            // A route change can invalidate render time before its notification
            // arrives. Preserve approximate position instead of restarting at zero.
            let elapsed = playbackStartedAt.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0
            return min(fileInfo.duration, positionSnapshot + elapsed)
        }

        let offset = Double(startFrame) / sampleRate
        // Render timing can briefly be negative during preroll after
        // rescheduling; never report time before the requested position.
        let elapsed = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        return min(fileInfo.duration, max(0, offset + elapsed))
    }

    var volume: Float {
        get { audioEngine.mainMixerNode.outputVolume }
        set {
            guard newValue.isFinite else { return }
            audioEngine.mainMixerNode.outputVolume = min(1, max(0, newValue))
        }
    }

    #if os(iOS)
    init(notificationCenter: NotificationCenter = .default, audioEngine: AVAudioEngine? = nil) {
        self.notificationCenter = notificationCenter
        self.audioEngine = audioEngine ?? AVAudioEngine()
        attachNodes()
        observeAudioNotifications()
    }
    #else
    init() {
        audioEngine = AVAudioEngine()
        attachNodes()
    }
    #endif

    isolated deinit {
        #if os(iOS)
        removeAudioObservers()
        #endif
        stop()
    }

    private func attachNodes() {
        equalizer.bypass = true
        audioEngine.attach(playerNode)
        audioEngine.attach(equalizer)
    }

    private func connectNodes(format: AVAudioFormat) throws {
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.disconnectNodeOutput(equalizer)
        try audioEngine.connectNode(playerNode, to: equalizer, format: format)
        try audioEngine.connectNode(equalizer, to: audioEngine.mainMixerNode, format: format)
    }

    func loadFile(at url: URL) async throws -> AudioFileInfo {
        guard url.isFileURL else { throw PlaybackError.localFileRequired }

        let requestID = UUID()
        loadID = requestID
        let prepared = try await Self.prepareFile(at: url)

        guard loadID == requestID, !Task.isCancelled else {
            prepared.file.close()
            throw CancellationError()
        }

        resetLoadedAudio(deactivatingSession: false)
        do {
            try connectNodes(format: prepared.file.processingFormat)
        } catch {
            prepared.file.close()
            throw error
        }

        file = prepared.file
        fileInfo = prepared.info
        frameCount = prepared.frameCount
        sampleRate = prepared.file.processingFormat.sampleRate
        return prepared.info
    }

    func play() throws {
        guard let fileInfo else { throw PlaybackError.noFileLoaded }
        guard !isPlaying else { return }

        if !hasScheduledAudio {
            let frame = positionSnapshot >= fileInfo.duration ? 0 : AVAudioFramePosition(positionSnapshot * sampleRate)
            scheduleAudio(from: frame)
        }

        #if os(iOS)
        if !isAudioSessionActive {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
            isAudioSessionActive = true
        }
        #endif

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            try playerNode.playAudio()
        } catch {
            audioEngine.pause()
            deactivateAudioSession()
            throw error
        }

        playbackStartedAt = ProcessInfo.processInfo.systemUptime
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }

        positionSnapshot = position
        scheduleID = UUID()
        playerNode.stop()
        audioEngine.pause()
        isPlaying = false
        hasScheduledAudio = false
        playbackStartedAt = nil
        deactivateAudioSession()
    }

    func stop() { resetLoadedAudio(deactivatingSession: true) }

    func stopForTrackChange() { resetLoadedAudio(deactivatingSession: false) }

    private func resetLoadedAudio(deactivatingSession: Bool) {
        loadID = UUID()
        scheduleID = UUID()
        playerNode.stop()
        audioEngine.stop()
        file?.close()
        file = nil
        fileInfo = nil
        frameCount = 0
        sampleRate = 0
        startFrame = 0
        positionSnapshot = 0
        isPlaying = false
        hasScheduledAudio = false
        playbackStartedAt = nil
        if deactivatingSession { deactivateAudioSession() }
    }

    func seek(to position: TimeInterval) throws {
        guard let fileInfo else { throw PlaybackError.noFileLoaded }
        guard position.isFinite else { throw PlaybackError.invalidPosition }

        let target = min(fileInfo.duration, max(0, position))
        let frame = target >= fileInfo.duration
            ? frameCount
            : AVAudioFramePosition(target * sampleRate)
        let wasPlaying = isPlaying

        scheduleAudio(from: frame)
        if wasPlaying {
            if frame == frameCount {
                finishPlayback(for: scheduleID)
            } else {
                try play()
            }
        }
    }

    private func scheduleAudio(from frame: AVAudioFramePosition) {
        let id = UUID()
        scheduleID = id
        playerNode.stop()
        playbackStartedAt = nil
        isPlaying = false
        hasScheduledAudio = false
        startFrame = frame
        positionSnapshot = Double(frame) / sampleRate

        guard let file, frame < frameCount else { return }

        // Segments use a UInt32 frame count. Queue chunks for unusually long files.
        var nextFrame = frame
        while nextFrame < frameCount {
            let count = AVAudioFrameCount(min(frameCount - nextFrame, Int64(UInt32.max)))
            let isLastSegment = nextFrame + Int64(count) == frameCount

            if isLastSegment {
                playerNode.scheduleSegment(
                    file,
                    startingFrame: nextFrame,
                    frameCount: count,
                    at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { [weak self] callbackType in
                    guard callbackType == .dataPlayedBack else { return }
                    // Never stop a player node directly from its completion callback.
                    Task { @MainActor [weak self] in
                        self?.finishPlayback(for: id)
                    }
                }
            } else {
                playerNode.scheduleSegment(
                    file,
                    startingFrame: nextFrame,
                    frameCount: count,
                    at: nil
                )
            }

            nextFrame += Int64(count)
        }
        hasScheduledAudio = true
    }

    private func finishPlayback(for id: UUID) {
        guard scheduleID == id, let fileInfo else { return }

        scheduleID = UUID()
        positionSnapshot = fileInfo.duration
        isPlaying = false
        hasScheduledAudio = false
        playerNode.stop()
        audioEngine.pause()
        playbackStartedAt = nil
        // Player decides whether to advance or stop; do not release the session
        // during the asynchronous handoff to the next file.
        onPlaybackEnded?()
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        guard isAudioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionActive = false
        #endif
    }

    #if os(iOS)
    private func observeAudioNotifications() {
        let session = AVAudioSession.sharedInstance()
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: nil
        ) { [weak self] notification in
            guard let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext,
                  context.source == .system else { return }
            let wasInterrupted = context.interruptionContext != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore app-requested deactivation from our own Pause/Stop.
                self.isAudioSessionActive = false
                self.onPlaybackEvent?(wasInterrupted ? .interruptionBegan : .outputUnavailable)
            }
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification, object: session, queue: nil
        ) { [weak self] notification in
            guard let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext else { return }
            let shouldResume = context.recommendation == .shouldResume
            Task { @MainActor [weak self] in
                self?.onPlaybackEvent?(.interruptionEnded(shouldResume: shouldResume))
            }
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: nil
        ) { [weak self] notification in
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in
                // Never unexpectedly switch headphone playback to the speaker.
                self?.onPlaybackEvent?(.outputUnavailable)
            }
        })
        let engineID = ObjectIdentifier(audioEngine)
        notificationObservers.append(notificationCenter.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: nil
        ) { [weak self] _ in
            // Engine notifications originate on an internal queue. Never tear
            // down or restart audio synchronously inside that callback.
            Task { @MainActor [weak self] in
                guard let self, ObjectIdentifier(self.audioEngine) == engineID else { return }
                self.recoverConfiguration()
            }
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification, object: session, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isAudioSessionActive = false
                self?.onPlaybackEvent?(.outputUnavailable)
            }
        })
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetMediaServices() }
        })
    }

    private func removeAudioObservers() {
        for observer in notificationObservers { notificationCenter.removeObserver(observer) }
        notificationObservers.removeAll()
    }

    private func recoverConfiguration() {
        guard let file, let fileInfo, !audioEngine.isRunning else { return }
        let target = position
        let wasPlaying = isPlaying
        scheduleID = UUID()
        playerNode.stop()
        audioEngine.stop()
        isPlaying = false
        hasScheduledAudio = false
        playbackStartedAt = nil
        positionSnapshot = target
        do {
            try connectNodes(format: file.processingFormat)
            if wasPlaying {
                if target >= fileInfo.duration {
                    finishPlayback(for: scheduleID)
                } else {
                    try play()
                }
            }
            onPlaybackEvent?(.configurationChanged)
        } catch {
            deactivateAudioSession()
            onPlaybackEvent?(.failed(error.localizedDescription))
        }
    }

    private func resetMediaServices() {
        let chosenVolume = volume
        isAudioSessionActive = false
        removeAudioObservers()
        resetLoadedAudio(deactivatingSession: false)
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        equalizer = AVAudioUnitEQ(numberOfBands: 10)
        attachNodes()
        volume = chosenVolume
        observeAudioNotifications()
        onPlaybackEvent?(.mediaServicesReset)
    }
    #endif

    // The file reader is prepared off the main actor, then transferred exclusively
    // to this engine. No file reader is shared between the two execution contexts.
    private nonisolated struct PreparedFile {
        let file: AVAudioFile
        let info: AudioFileInfo
        let frameCount: AVAudioFramePosition
    }

    @concurrent
    private nonisolated static func prepareFile(at url: URL) async throws -> sending PreparedFile {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        let length = file.length
        let format = file.processingFormat

        guard length > 0, format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            file.close()
            throw PlaybackError.invalidAudioFile
        }

        do {
            try Task.checkCancellation()
        } catch {
            file.close()
            throw error
        }

        return PreparedFile(
            file: file,
            info: AudioFileInfo(duration: Double(length) / format.sampleRate),
            frameCount: length
        )
    }

    private nonisolated enum PlaybackError: LocalizedError {
        case localFileRequired
        case noFileLoaded
        case invalidAudioFile
        case invalidPosition

        var errorDescription: String? {
            switch self {
            case .localFileRequired:
                return "Only local audio files can be played."
            case .noFileLoaded:
                return "No audio file is loaded."
            case .invalidAudioFile:
                return "The file does not contain playable audio."
            case .invalidPosition:
                return "The playback position must be a finite number."
            }
        }
    }
}

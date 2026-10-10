import AVFAudio
import Foundation

@MainActor
final class AVFilePlaybackEngine: FilePlaybackEngine {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)

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

    #if os(iOS) || os(visionOS)
    private var isAudioSessionActive = false
    #endif

    var onPlaybackEnded: (@MainActor () -> Void)?

    var position: TimeInterval {
        guard let fileInfo else { return 0 }
        guard isPlaying,
              let renderTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: renderTime),
              playerTime.isSampleTimeValid,
              playerTime.sampleRate > 0 else {
            return positionSnapshot
        }

        let offset = Double(startFrame) / sampleRate
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        return min(fileInfo.duration, max(0, offset + elapsed))
    }

    var volume: Float {
        get { audioEngine.mainMixerNode.outputVolume }
        set {
            guard newValue.isFinite else { return }
            audioEngine.mainMixerNode.outputVolume = min(1, max(0, newValue))
        }
    }

    init() {
        equalizer.bypass = true
        audioEngine.attach(playerNode)
        audioEngine.attach(equalizer)
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

        stop()
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.disconnectNodeOutput(equalizer)
        do {
            try audioEngine.connectNode(playerNode, to: equalizer, format: prepared.file.processingFormat)
            try audioEngine.connectNode(equalizer, to: audioEngine.mainMixerNode, format: prepared.file.processingFormat)
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
            let frame = positionSnapshot >= fileInfo.duration ? 0 : startFrame
            scheduleAudio(from: frame)
        }

        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        isAudioSessionActive = true
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

        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }

        positionSnapshot = position
        playerNode.pause()
        audioEngine.pause()
        isPlaying = false
        deactivateAudioSession()
    }

    func stop() {
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
        deactivateAudioSession()
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
        deactivateAudioSession()
        onPlaybackEnded?()
    }

    private func deactivateAudioSession() {
        #if os(iOS) || os(visionOS)
        guard isAudioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionActive = false
        #endif
    }

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

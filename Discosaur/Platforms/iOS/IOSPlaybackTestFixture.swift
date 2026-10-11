#if DEBUG && os(iOS)
import AVFAudio
import Foundation

// UI tests can opt into real, silent audio without importing from Files or
// touching the normal library. Release builds do not contain this fixture.
@MainActor
enum IOSPlaybackTestFixture {
    static func prepareIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DISCOSAUR_TEST_PLAYBACK_FIXTURE"] == "1",
              environment["DISCOSAUR_TEST_LIBRARY_ID"].flatMap(UUID.init(uuidString:)) != nil else { return }

        let libraryURL = LibraryStorageLocation.current
        guard !FileManager.default.fileExists(atPath: libraryURL.path) else { return }

        do {
            let directory = libraryURL.deletingLastPathComponent().appendingPathComponent("Audio", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let duration = environment["DISCOSAUR_TEST_TRACK_DURATION"].flatMap(Double.init)
                .flatMap { $0.isFinite && (10...600).contains($0) ? $0 : nil } ?? 60
            let sampleRate: Double = 44_100
            let frames = AVAudioFrameCount(duration * sampleRate)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0] else {
                throw CocoaError(.fileWriteUnknown)
            }
            buffer.frameLength = frames
            samples.initialize(repeating: 0, count: Int(frames))

            var tracks: [Track] = []
            for number in 1...3 {
                let url = directory.appendingPathComponent("Track \(number).wav")
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
                file.close()
                tracks.append(Track(
                    url: url,
                    metadata: TrackMetadata(title: "Test Track \(number)", artist: "Test Artist", duration: duration),
                    album: nil
                ))
            }
            let playlist = Playlist(name: "Playback Tests", tracks: tracks)
            try await Storage(fileURL: libraryURL).save(LibrarySnapshot(playlists: [playlist]))
        } catch {
            assertionFailure("Could not prepare playback UI fixture: \(error)")
        }
    }
}
#endif

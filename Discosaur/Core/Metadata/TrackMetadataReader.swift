import Foundation

nonisolated protocol TrackMetadataReading: Sendable {
    // All metadata is optional and can be missing, in the
    // worse case we will end up only with the filename
    func read(at url: URL) async throws -> TrackMetadata
}

extension TrackMetadataReading {
    @concurrent
    func readTracks(_ tracks: [Track]) async throws -> [Track] {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (Int, Track).self) { group in
            var result = tracks
            var remaining = tracks.enumerated().makeIterator()

            // Limit simultaneous file reads, while preserving the scanned order.
            for _ in 0..<8 {
                guard let (index, track) = remaining.next() else { break }
                group.addTask {
                    (index, try await readTrack(track))
                }
            }

            for try await (index, track) in group {
                try Task.checkCancellation()
                result[index] = track
                if let (nextIndex, nextTrack) = remaining.next() {
                    group.addTask {
                        (nextIndex, try await readTrack(nextTrack))
                    }
                }
            }

            try Task.checkCancellation()
            return result
        }
    }

    private func readTrack(_ track: Track) async throws -> Track {
        try Task.checkCancellation()
        let metadata: TrackMetadata
        do {
            metadata = try await read(at: track.url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A broken tag or unsupported format must not reject the playlist.
            metadata = TrackMetadata()
        }
        try Task.checkCancellation()
        return Track(url: track.url, metadata: metadata)
    }
}

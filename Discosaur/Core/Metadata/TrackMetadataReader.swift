import Foundation

nonisolated protocol TrackMetadataReading: Sendable {
    // All metadata is optional and can be missing, in the
    // worse case we will end up only with the filename
    func read(at url: URL) async throws -> TrackMetadata
}

extension TrackMetadataReading {
    @concurrent
    func readMetadata(for tracks: [Track]) async throws -> [(url: URL, metadata: TrackMetadata, location: FileLocation?)] {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (Int, TrackMetadata).self) { group in
            var result = tracks.map { (url: $0.url, metadata: TrackMetadata(), location: $0.location) }
            var remaining = tracks.enumerated().makeIterator()

            // Limit simultaneous file reads, while preserving the scanned order.
            // Keep raw tags until albums are resolved, then build the runtime tracks.
            for _ in 0..<8 {
                guard let (index, track) = remaining.next() else { break }
                group.addTask {
                    (index, try await readMetadata(at: track.url))
                }
            }

            for try await (index, metadata) in group {
                try Task.checkCancellation()
                result[index].metadata = metadata
                if let (nextIndex, nextTrack) = remaining.next() {
                    group.addTask {
                        (nextIndex, try await readMetadata(at: nextTrack.url))
                    }
                }
            }

            try Task.checkCancellation()
            return result
        }
    }

    private func readMetadata(at url: URL) async throws -> TrackMetadata {
        try Task.checkCancellation()
        let metadata: TrackMetadata
        do {
            metadata = try await read(at: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A broken tag or unsupported format must not reject the playlist.
            metadata = TrackMetadata()
        }
        try Task.checkCancellation()
        return metadata
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class AlbumArtworkCache {
    private var images: [FileLocation: Data] = [:]
    @ObservationIgnored private var loads: [FileLocation: Task<Void, Never>] = [:]
    @ObservationIgnored private let fileAccessManager: FileAccessManager
    @ObservationIgnored private let reader: any AlbumArtworkReading

    init(
        fileAccessManager: FileAccessManager,
        reader: any AlbumArtworkReading = AlbumArtworkReader()
    ) {
        self.fileAccessManager = fileAccessManager
        self.reader = reader
    }

    func data(for location: FileLocation?) -> Data? {
        guard let location else { return nil }
        return images[location]
    }

    func load(for playlist: Playlist) async {
        var seen: Set<FileLocation> = []
        for track in playlist.tracks {
            guard !Task.isCancelled else { return }
            if let location = track.album?.coverLocation, seen.insert(location).inserted {
                await load(location)
            }
        }
    }

    func load(_ location: FileLocation?) async {
        guard let location, !Task.isCancelled, images[location] == nil else { return }
        if let task = loads[location] {
            await task.value
            return
        }

        let task = Task {
            defer { loads[location] = nil }
            do {
                let access = try fileAccessManager.acquire(location)
                defer { access.close() }
                if let data = try await reader.read(at: access.resourceURL) {
                    images[location] = data
                }
            } catch {
                // Artwork is optional. Keep the reference and retry on a later load,
                // e.g. when a disconnected volume becomes available again.
            }
        }
        loads[location] = task
        await task.value
    }
}

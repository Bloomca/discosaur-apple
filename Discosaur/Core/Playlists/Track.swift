import Foundation

nonisolated struct Track: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String?
    let artist: String?
    let album: Album?
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval?

    var id: URL { url }
    var fileName: String { url.lastPathComponent }
    var name: String { title ?? fileName }

    init(url: URL) {
        self.init(url: url, metadata: TrackMetadata(), album: nil)
    }

    init(url: URL, metadata: TrackMetadata, album: Album?) {
        self.url = url.standardizedFileURL
        title = metadata.title
        artist = metadata.artist
        self.album = album
        trackNumber = metadata.trackNumber
        discNumber = metadata.discNumber
        duration = metadata.duration
    }
}

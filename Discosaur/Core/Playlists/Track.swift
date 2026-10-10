import Foundation

nonisolated struct Track: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String?
    let artist: String?
    let album: String?
    let albumArtist: String?
    let year: Int?
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval?

    var id: URL { url }
    var fileName: String { url.lastPathComponent }
    var name: String { title ?? fileName }

    init(url: URL, metadata: TrackMetadata = TrackMetadata()) {
        self.url = url.standardizedFileURL
        title = metadata.title
        artist = metadata.artist
        album = metadata.album
        albumArtist = metadata.albumArtist
        year = metadata.year
        trackNumber = metadata.trackNumber
        discNumber = metadata.discNumber
        duration = metadata.duration
    }
}

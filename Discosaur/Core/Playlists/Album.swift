import Foundation

nonisolated struct Album: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String?
    let artist: String?
    let year: Int?
    // Artwork uses an existing source grant; image bytes belong to the runtime cache.
    let coverLocation: FileLocation?

    init(
        id: UUID = UUID(),
        title: String?,
        artist: String?,
        year: Int?,
        coverLocation: FileLocation? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.coverLocation = coverLocation
    }
}

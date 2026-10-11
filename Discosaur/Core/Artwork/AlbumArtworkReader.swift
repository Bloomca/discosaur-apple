import Foundation
import ImageIO

nonisolated protocol AlbumArtworkReading: Sendable {
    func read(at url: URL) async throws -> Data?
}

nonisolated struct AlbumArtworkReader: AlbumArtworkReading {
    @concurrent
    func read(at url: URL) async throws -> Data? {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url)
        try Task.checkCancellation()
        // Inspect the image without decoding its pixels or storing UI image types.
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(image) > 0,
              CGImageSourceGetStatus(image) == .statusComplete else { return nil }
        return data
    }
}

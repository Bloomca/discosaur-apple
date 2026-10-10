import Foundation

nonisolated struct TrackMetadata: Equatable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let albumArtist: String?
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval?

    init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        self.title = title.flatMap(Self.normalizedText)
        self.artist = artist.flatMap(Self.normalizedText)
        self.album = album.flatMap(Self.normalizedText)
        self.albumArtist = albumArtist.flatMap(Self.normalizedText)
        self.trackNumber = Self.validatedNumber(trackNumber)
        self.discNumber = Self.validatedNumber(discNumber)
        self.duration = Self.validatedDuration(duration)
    }

    static func validatedDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    static func sequenceNumber(from text: String?) -> Int? {
        // ID3 and Core Audio can represent a track/disc as "03" or "3/12".
        guard let text,
              let first = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first,
              let number = Int(first.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return validatedNumber(number)
    }

    private static func validatedNumber(_ number: Int?) -> Int? {
        guard let number, number > 0 else { return nil }
        return number
    }

    private static func normalizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

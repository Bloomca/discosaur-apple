import Foundation

nonisolated struct Playlist: Identifiable, Equatable, Sendable {
    let id = UUID()
    let tracks: [Track]

    @concurrent
    static func sortedTracks(_ tracks: [Track]) async throws -> [Track] {
        try Task.checkCancellation()
        let sorted = tracks.sorted(by: comesBefore)
        try Task.checkCancellation()
        return sorted
    }

    private static func comesBefore(_ left: Track, _ right: Track) -> Bool {
        // Numbers are only meaningful within an album, not across a library.
        if let leftAlbum = left.album, let rightAlbum = right.album {
            let albumOrder = leftAlbum.localizedStandardCompare(rightAlbum)
            if albumOrder != .orderedSame {
                return albumOrder == .orderedAscending
            }

            // Use album artist, not track artist, so compilations stay together.
            let artistOrder = (left.albumArtist ?? "").localizedStandardCompare(right.albumArtist ?? "")
            if artistOrder != .orderedSame {
                return artistOrder == .orderedAscending
            }
        } else if left.album != nil {
            return true
        } else if right.album != nil {
            return false
        } else {
            // Without album tags, keep separate source folders together.
            let folderOrder = left.url.deletingLastPathComponent().path.localizedStandardCompare(
                right.url.deletingLastPathComponent().path
            )
            if folderOrder != .orderedSame {
                return folderOrder == .orderedAscending
            }
        }

        let leftDisc = left.discNumber ?? 1
        let rightDisc = right.discNumber ?? 1
        if leftDisc != rightDisc {
            return leftDisc < rightDisc
        }

        let leftNumber = left.trackNumber ?? Int.max
        let rightNumber = right.trackNumber ?? Int.max
        if leftNumber != rightNumber {
            return leftNumber < rightNumber
        }

        let fileOrder = left.fileName.localizedStandardCompare(right.fileName)
        if fileOrder != .orderedSame {
            return fileOrder == .orderedAscending
        }
        return left.url.path < right.url.path
    }
}

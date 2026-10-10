import Foundation

nonisolated struct Playlist: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let tracks: [Track]

    init(id: UUID = UUID(), tracks: [Track]) {
        self.id = id
        self.name = "New playlist"
        self.tracks = tracks
    }

    @concurrent
    static func sortedTracks(_ tracks: [Track]) async throws -> [Track] {
        try Task.checkCancellation()
        let sorted = tracks.sorted(by: comesBefore)
        try Task.checkCancellation()
        return sorted
    }

    static func comesBefore(_ left: Track, _ right: Track) -> Bool {
        // Numbers are only meaningful within an album, not across a library.
        if let leftTitle = left.album?.title, let rightTitle = right.album?.title {
            let albumOrder = leftTitle.localizedStandardCompare(rightTitle)
            if albumOrder != .orderedSame {
                return albumOrder == .orderedAscending
            }

            // Use album artist, not track artist, so compilations stay together.
            let artistOrder = (left.album?.artist ?? "").localizedStandardCompare(right.album?.artist ?? "")
            if artistOrder != .orderedSame {
                return artistOrder == .orderedAscending
            }
        } else if left.album?.title != nil {
            return true
        } else if right.album?.title != nil {
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

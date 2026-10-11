import Foundation

nonisolated struct AlbumGroup: Identifiable, Equatable, Sendable {
    enum ID: Hashable, Sendable {
        case album(title: String, artist: String?, year: Int?, sourceFolder: URL?)
        case folder(URL)
    }

    let id: ID
    let title: String
    let artist: String
    let coverLocation: FileLocation?
    let trackIndices: [Int]

    private static func id(for track: Track) -> ID {
        let folder = track.url.deletingLastPathComponent()
        guard let title = track.album?.title else { return .folder(folder) }
        let artist = track.album?.artist.map(normalized)
        return .album(
            title: normalized(title),
            artist: artist,
            year: track.album?.year,
            // Known album artists let multi-disc albums span folders. Without
            // one, keep unrelated, identically named albums in separate folders.
            sourceFolder: artist == nil ? folder : nil
        )
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    static func groups(in playlist: Playlist) -> [AlbumGroup] {
        var orderedIDs: [ID] = []
        var indicesByID: [ID: [Int]] = [:]
        for (index, track) in playlist.tracks.enumerated() {
            let id = id(for: track)
            if indicesByID[id] == nil {
                orderedIDs.append(id)
            }
            indicesByID[id, default: []].append(index)
        }

        return orderedIDs.compactMap { id in
            guard let indices = indicesByID[id] else { return nil }
            let sortedIndices = indices.sorted {
                Playlist.comesBefore(playlist.tracks[$0], playlist.tracks[$1])
            }
            guard let firstIndex = sortedIndices.first else { return nil }
            let tracks = sortedIndices.map { playlist.tracks[$0] }
            let first = playlist.tracks[firstIndex]
            let folderTitle = first.url.deletingLastPathComponent().lastPathComponent
            let albumArtist = tracks.lazy.compactMap { $0.album?.artist }.first
            let trackArtists = tracks.compactMap(\.artist)
            let distinctArtists = Set(trackArtists.map(normalized))
            let artist = albumArtist ?? (distinctArtists.count > 1
                ? "Various artists"
                : trackArtists.first ?? "Unknown artist")

            return AlbumGroup(
                id: id,
                title: first.album?.title ?? (folderTitle.isEmpty ? "Unknown album" : folderTitle),
                artist: artist,
                coverLocation: tracks.lazy.compactMap { $0.album?.coverLocation }.first,
                trackIndices: sortedIndices
            )
        }
    }
}

extension Playlist {
    var albumGroups: [AlbumGroup] { AlbumGroup.groups(in: self) }
}

import Foundation

// Keep the versioned disk schema independent of observable/runtime model changes.
nonisolated struct LibraryDocumentV1: Codable {
    let version: Int
    let sources: [SourceRecord]
    let playlists: [PlaylistRecord]

    init(snapshot: LibrarySnapshot) {
        version = 1
        sources = snapshot.sources.map(SourceRecord.init)
        playlists = snapshot.playlists.map(PlaylistRecord.init)
    }

    func snapshot() throws -> LibrarySnapshot {
        let snapshot = LibrarySnapshot(
            playlists: try playlists.map { try $0.playlist() },
            sources: sources.map { $0.source }
        )
        try snapshot.validate()
        return snapshot
    }

    struct SourceRecord: Codable {
        enum Kind: String, Codable { case file, folder }
        let id: UUID
        let kind: Kind
        let bookmarkData: Data

        init(_ source: FileSource) {
            id = source.id
            switch source.kind {
            case .file: kind = .file
            case .folder: kind = .folder
            }
            bookmarkData = source.bookmarkData
        }

        var source: FileSource {
            let sourceKind: FileSource.Kind
            switch kind {
            case .file: sourceKind = .file
            case .folder: sourceKind = .folder
            }
            return FileSource(id: id, kind: sourceKind, bookmarkData: bookmarkData)
        }
    }

    struct PlaylistRecord: Codable {
        let id: UUID
        let name: String
        let tracks: [TrackRecord]

        init(_ playlist: Playlist) {
            id = playlist.id
            name = playlist.name
            tracks = playlist.tracks.map(TrackRecord.init)
        }

        func playlist() throws -> Playlist {
            Playlist(id: id, name: name, tracks: try tracks.map { try $0.track() })
        }
    }

    struct TrackRecord: Codable {
        let url: URL
        let location: FileLocation?
        let title: String?
        let artist: String?
        let album: Album?
        let trackNumber: Int?
        let discNumber: Int?
        let duration: TimeInterval?

        init(_ track: Track) {
            url = track.url
            location = track.location
            title = track.title
            artist = track.artist
            album = track.album
            trackNumber = track.trackNumber
            discNumber = track.discNumber
            duration = track.duration
        }

        func track() throws -> Track {
            guard trackNumber.map({ $0 > 0 }) ?? true,
                  discNumber.map({ $0 > 0 }) ?? true,
                  duration.map({ TrackMetadata.validatedDuration($0) != nil }) ?? true else {
                throw StorageError.invalidLibrary("Invalid track numbers or duration.")
            }
            return Track(
                url: url,
                metadata: TrackMetadata(
                    title: title, artist: artist, trackNumber: trackNumber,
                    discNumber: discNumber, duration: duration
                ),
                album: album,
                location: location
            )
        }
    }
}

nonisolated extension LibrarySnapshot {
    // Validate relationships and paths, not availability. Disconnected volumes,
    // missing media, and stale/unresolvable bookmarks must not discard entries.
    func validate() throws {
        guard Set(sources.map(\.id)).count == sources.count else {
            throw StorageError.invalidLibrary("Duplicate file source identifiers.")
        }
        guard Set(playlists.map(\.id)).count == playlists.count else {
            throw StorageError.invalidLibrary("Duplicate playlist identifiers.")
        }
        guard sources.allSatisfy({ !$0.bookmarkData.isEmpty }) else {
            throw StorageError.invalidLibrary("A file source has an empty bookmark.")
        }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for playlist in playlists {
            var trackIDs: Set<URL> = []
            for track in playlist.tracks {
                guard track.url.isFileURL else {
                    throw StorageError.invalidLibrary("A track URL is not a local file.")
                }
                guard trackIDs.insert(track.url.standardizedFileURL).inserted else {
                    throw StorageError.invalidLibrary("Duplicate tracks in playlist ‘\(playlist.name)’.")
                }
                if let year = track.album?.year, TrackMetadata.validatedYear(year) == nil {
                    throw StorageError.invalidLibrary("Invalid album year.")
                }
                for location in [track.location, track.album?.coverLocation].compactMap({ $0 }) {
                    guard let source = sourcesByID[location.sourceID] else {
                        throw StorageError.invalidLibrary("A track or cover references an unknown file source.")
                    }
                    do {
                        try location.validate(kind: source.kind)
                    } catch {
                        throw StorageError.invalidLibrary(error.localizedDescription)
                    }
                }
            }
        }
    }
}

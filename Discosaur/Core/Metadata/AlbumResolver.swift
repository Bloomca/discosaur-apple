import Foundation

nonisolated struct AlbumResolver: Sendable {
    @concurrent
    func resolve(
        _ files: [(url: URL, metadata: TrackMetadata, location: FileLocation?)],
        selectedFolders: [(url: URL, sourceID: UUID)]
    ) async throws -> [Track] {
        try Task.checkCancellation()

        // Only explicitly selected folders authorize searching for external artwork.
        // Prefer the most specific grant, just as track locations do.
        let selectedFolders = selectedFolders.filter { $0.url.isFileURL }.map {
            (url: $0.url.standardizedFileURL.resolvingSymlinksInPath(), sourceID: $0.sourceID)
        }.sorted { $0.url.pathComponents.count > $1.url.pathComponents.count }

        var albumsByIndex = [Album?](repeating: nil, count: files.count)
        var indicesByAlbum: [SourceAlbum: [Int]] = [:]
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            guard let title = file.metadata.album else {
                // Without a title, preserve other album tags without guessing identity.
                if file.metadata.albumArtist != nil || file.metadata.year != nil {
                    albumsByIndex[index] = Album(
                        title: nil,
                        artist: file.metadata.albumArtist,
                        year: file.metadata.year,
                        coverLocation: nil
                    )
                }
                continue
            }
            let key = SourceAlbum(
                folder: file.url.deletingLastPathComponent(),
                title: normalized(title)
            )
            indicesByAlbum[key, default: []].append(index)
        }

        var checkedFolders: Set<URL> = []
        var coversByFolder: [URL: FileLocation] = [:]
        for (source, indices) in indicesByAlbum {
            try Task.checkCancellation()
            // Cache both successful and missing covers across albums in a folder.
            if checkedFolders.insert(source.folder).inserted,
               let location = try coverLocation(in: source.folder, selectedFolders: selectedFolders) {
                coversByFolder[source.folder] = location
            }

            for group in artistGroups(for: indices, in: files) {
                try Task.checkCancellation()
                for yearGroup in yearGroups(for: group.indices, in: files) {
                    try Task.checkCancellation()
                    guard let firstIndex = yearGroup.indices.first else { continue }
                    let album = Album(
                        title: files[firstIndex].metadata.album,
                        artist: group.artist,
                        year: yearGroup.year,
                        coverLocation: coversByFolder[source.folder]
                    )
                    for index in yearGroup.indices {
                        try Task.checkCancellation()
                        albumsByIndex[index] = album
                    }
                }
            }
        }

        // Runtime tracks contain resolved albums, not a second copy of their raw tags.
        return try files.enumerated().map { index, file in
            try Task.checkCancellation()
            return Track(url: file.url, metadata: file.metadata, album: albumsByIndex[index], location: file.location)
        }
    }

    private func artistGroups(
        for indices: [Int],
        in files: [(url: URL, metadata: TrackMetadata, location: FileLocation?)]
    ) -> [ArtistGroup] {
        var groups: [String: ArtistGroup] = [:]
        for index in indices {
            guard let artist = files[index].metadata.albumArtist else { continue }
            groups[normalized(artist), default: ArtistGroup(artist: artist, indices: [])]
                .indices.append(index)
        }

        // A single album artist also resolves tracks whose album-artist tag is missing.
        if groups.count == 1, let group = groups.values.first {
            return [ArtistGroup(artist: group.artist, indices: indices)]
        }
        if !groups.isEmpty {
            // Conflicting album artists stay separate. Retain partial albums for the
            // remaining tracks rather than discarding their title/year or guessing.
            var result = Array(groups.values)
            let unresolved = indices.filter { files[$0].metadata.albumArtist == nil }
            if !unresolved.isEmpty {
                result.append(ArtistGroup(artist: nil, indices: unresolved))
            }
            return result
        }

        // Infer an artist only when known track artists agree. A compilation without
        // album-artist tags still retains its album title, year, and artwork.
        let artists = indices.compactMap { files[$0].metadata.artist }
        let artist: String?
        if let first = artists.first, artists.allSatisfy({ normalized($0) == normalized(first) }) {
            artist = first
        } else {
            artist = nil
        }
        return [ArtistGroup(artist: artist, indices: indices)]
    }

    private func yearGroups(
        for indices: [Int],
        in files: [(url: URL, metadata: TrackMetadata, location: FileLocation?)]
    ) -> [(year: Int?, indices: [Int])] {
        let years = Set(indices.compactMap { files[$0].metadata.year })
        if years.count <= 1 {
            return [(year: years.first, indices: indices)]
        }
        // Don't erase conflicting years or arbitrarily choose one for every track.
        return Dictionary(grouping: indices, by: { files[$0].metadata.year })
            .map { (year: $0.key, indices: $0.value) }
    }

    private func coverLocation(
        in folder: URL,
        selectedFolders: [(url: URL, sourceID: UUID)]
    ) throws -> FileLocation? {
        // File-only imports must not enumerate their parent folders.
        let components = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard selectedFolders.contains(where: { components.starts(with: $0.url.pathComponents) }) else { return nil }
        try Task.checkCancellation()
        guard let files = try? FileManager().contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Discovery stores only a reference. Reading/validating image bytes is lazy.
        for name in ["cover.jpg", "folder.jpg"] {
            let candidates = files.filter { $0.lastPathComponent.lowercased() == name }
                .sorted { $0.path < $1.path }
            for url in candidates {
                try Task.checkCancellation()
                for source in selectedFolders {
                    // Check containment before inspecting a symlink's target.
                    guard let path = FileLocation.relativePath(of: url, inside: source.url),
                          let resources = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]),
                          resources.isRegularFile == true else { continue }
                    return .insideFolder(sourceID: source.sourceID, relativePath: path)
                }
            }
        }
        return nil
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    private struct SourceAlbum: Hashable {
        let folder: URL
        let title: String
    }

    private struct ArtistGroup {
        let artist: String?
        var indices: [Int]
    }
}

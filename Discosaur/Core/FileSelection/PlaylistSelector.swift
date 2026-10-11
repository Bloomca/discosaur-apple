import Foundation
import Observation

@MainActor
@Observable
final class PlaylistSelector {
    private(set) var isLoading = false
    var errorMessage: String?

    private let library: Library
    private let fileAccessManager: FileAccessManager
    private let scanner = TrackScanner()
    private let albumResolver = AlbumResolver()
    private let metadataReader: any TrackMetadataReading

    init(
        library: Library,
        fileAccessManager: FileAccessManager? = nil,
        metadataReader: any TrackMetadataReading = AVTrackMetadataReader()
    ) {
        self.library = library
        self.fileAccessManager = fileAccessManager ?? FileAccessManager(library: library)
        self.metadataReader = metadataReader
    }

    @discardableResult
    func selectFiles(_ urls: [URL]) async -> Playlist? {
        guard !isLoading, !Task.isCancelled else { return nil }

        // Keep importing into the original playlist if the selection changes mid-import.
        let playlistID = library.selectedPlaylistID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var prepared: [(source: FileSource, access: ScopedFileAccess)] = []
        defer {
            for selection in prepared {
                selection.access.close()
            }
        }

        do {
            for url in urls {
                try Task.checkCancellation()
                prepared.append(try fileAccessManager.prepareSource(for: url))
            }
            let selectedURLs = prepared.map { $0.access.resourceURL }
            let scannedTracks = try await scanner.tracks(from: selectedURLs)
            if let playlistID, library.playlist(id: playlistID) == nil { return nil }
            let destination = playlistID.flatMap { library.playlist(id: $0) } ?? library.selectedPlaylist
            let existingURLs = Set(destination?.tracks.map(\.url) ?? [])
            let newTracks = try scannedTracks.filter { !existingURLs.contains($0.url) }.map {
                Track(url: $0.url, location: try location(for: $0.url, in: prepared))
            }
            guard !newTracks.isEmpty else { return nil }

            let files = try await metadataReader.readMetadata(for: newTracks)
            let selectedFolders = prepared.filter { $0.source.kind == .folder }.map {
                (url: $0.access.resourceURL, sourceID: $0.source.id)
            }
            let tracks = try await albumResolver.resolve(files, selectedFolders: selectedFolders)
            let sortedTracks = try await Playlist.sortedTracks(tracks)
            try Task.checkCancellation()
            // Re-read the destination after suspension to preserve other imports/edits.
            // First imports can share a playlist created while this import was suspended.
            if let playlistID, library.playlist(id: playlistID) == nil { return nil }
            let currentDestination = playlistID.flatMap { library.playlist(id: $0) } ?? library.selectedPlaylist
            let existingTracks = currentDestination?.tracks ?? []
            let currentURLs = Set(existingTracks.map(\.url))
            let addedTracks = sortedTracks.filter { !currentURLs.contains($0.url) }
            guard !addedTracks.isEmpty else { return nil }

            // Commit only sources used by successfully imported tracks or their artwork.
            // Failed, cancelled, duplicate, and empty selections leave no orphaned sources.
            let usedSourceIDs = Set(addedTracks.flatMap { track in
                [track.location?.sourceID, track.album?.coverLocation?.sourceID].compactMap { $0 }
            })
            for selection in prepared where usedSourceIDs.contains(selection.source.id) {
                library.updateSource(selection.source)
            }

            // Preserve order, identity, and the latest name, including mid-import renames.
            let destinationPlaylist = currentDestination ?? Playlist(tracks: [])
            let playlist = Playlist(
                id: destinationPlaylist.id,
                name: destinationPlaylist.name,
                tracks: existingTracks + addedTracks
            )
            library.updatePlaylist(playlist)
            return playlist
        } catch is CancellationError {
            // Keep the library unchanged when selection is cancelled.
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    private func location(
        for url: URL,
        in prepared: [(source: FileSource, access: ScopedFileAccess)]
    ) throws -> FileLocation {
        // Prefer folder grants, including when the same track was explicitly selected.
        // More specific selected folders win over their parents.
        let folders = prepared.filter { $0.source.kind == .folder }.sorted {
            $0.access.resourceURL.pathComponents.count > $1.access.resourceURL.pathComponents.count
        }
        for folder in folders {
            if let path = FileLocation.relativePath(of: url, inside: folder.access.resourceURL) {
                return .insideFolder(sourceID: folder.source.id, relativePath: path)
            }
        }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        for file in prepared where file.source.kind == .file {
            if file.access.resourceURL.standardizedFileURL.resolvingSymlinksInPath() == canonicalURL {
                return .selectedFile(sourceID: file.source.id)
            }
        }
        throw FileAccessError.outsideSource(url)
    }
}

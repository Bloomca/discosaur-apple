import Foundation
import Observation

@MainActor
@Observable
final class PlaylistSelector {
    private(set) var isLoading = false
    var errorMessage: String?

    private let library: Library
    private let scanner = TrackScanner()
    private let albumResolver = AlbumResolver()
    private let metadataReader: any TrackMetadataReading

    init(library: Library, metadataReader: any TrackMetadataReading = AVTrackMetadataReader()) {
        self.library = library
        self.metadataReader = metadataReader
    }

    @discardableResult
    func selectFiles(_ urls: [URL]) async -> Playlist? {
        guard !isLoading, !Task.isCancelled else { return nil }

        // Keep importing into the original playlist if the selection changes mid-import.
        let playlistID = library.currentPlaylistID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Keep selected folder/file grants alive for scanning, metadata, and cover reads.
        // Child track URLs may not have security-scoped grants of their own.
        let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in scopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let scannedTracks = try await scanner.tracks(from: urls)
            let destination = playlistID.flatMap { library.playlist(id: $0) } ?? library.currentPlaylist
            let existingURLs = Set(destination?.tracks.map(\.url) ?? [])
            let newTracks = scannedTracks.filter { !existingURLs.contains($0.url) }
            guard !newTracks.isEmpty else { return nil }

            let files = try await metadataReader.readMetadata(for: newTracks)
            let tracks = try await albumResolver.resolve(files, selectedURLs: urls)
            let sortedTracks = try await Playlist.sortedTracks(tracks)
            try Task.checkCancellation()
            // Re-read the destination after suspension to preserve other imports/edits.
            // First imports can share a playlist created while this import was suspended.
            let currentDestination = playlistID.flatMap { library.playlist(id: $0) } ?? library.currentPlaylist
            let existingTracks = currentDestination?.tracks ?? []
            let currentURLs = Set(existingTracks.map(\.url))
            let addedTracks = sortedTracks.filter { !currentURLs.contains($0.url) }
            guard !addedTracks.isEmpty else { return nil }

            // Keep existing order and identity, appending only the new sorted batch.
            let playlist = Playlist(id: currentDestination?.id ?? UUID(), tracks: existingTracks + addedTracks)
            library.updatePlaylist(playlist)
            return playlist
        } catch is CancellationError {
            // Keep the current playlist when selection is cancelled.
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }
}

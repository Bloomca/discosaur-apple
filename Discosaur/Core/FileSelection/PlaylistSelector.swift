import Foundation
import Observation

@MainActor
@Observable
final class PlaylistSelector {
    private(set) var playlist: Playlist?
    private(set) var isLoading = false
    var errorMessage: String?

    private let scanner = TrackScanner()
    private let albumResolver = AlbumResolver()
    private let metadataReader: any TrackMetadataReading

    init(metadataReader: any TrackMetadataReading = AVTrackMetadataReader()) {
        self.metadataReader = metadataReader
    }

    func selectFiles(_ urls: [URL]) async {
        guard !isLoading, !Task.isCancelled else { return }

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
            let files = try await metadataReader.readMetadata(for: scannedTracks)
            let tracks = try await albumResolver.resolve(files, selectedURLs: urls)
            let sortedTracks = try await Playlist.sortedTracks(tracks)
            try Task.checkCancellation()
            playlist = Playlist(tracks: sortedTracks)
        } catch is CancellationError {
            // Keep the current playlist when selection is cancelled.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class PlaylistSelector {
    private(set) var playlist: Playlist?
    private(set) var isLoading = false
    var errorMessage: String?

    private let scanner = TrackScanner()

    func selectFiles(_ urls: [URL]) async {
        guard !isLoading, !Task.isCancelled else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let tracks = try await scanner.tracks(from: urls)
            try Task.checkCancellation()
            playlist = Playlist(tracks: tracks)
        } catch is CancellationError {
            // Keep the current playlist when selection is cancelled.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

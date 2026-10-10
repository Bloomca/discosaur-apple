import Foundation
import SwiftUI

struct TrackRow: View {
    let track: Track
    let player: Player
    let onPlaybackError: (Error) -> Void

    @State private var isHovered = false
    @FocusState private var isPlaybackFocused: Bool

    private var isPlaying: Bool {
        player.currentTrack == track && player.status == .playing
    }

    private var isLoading: Bool {
        player.currentTrack == track && player.isLoading
    }

    private var showsPlaybackControl: Bool {
        #if os(macOS)
        isHovered || isPlaying || isLoading || isPlaybackFocused
        #else
        true
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isPlaybackFocused)
            .disabled(isLoading)
            .opacity(showsPlaybackControl ? 1 : 0)
            .help(isPlaying ? "Pause" : "Play")
            .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(track.name)")
            .accessibilityIdentifier("playback-\(track.url.absoluteString)")

            Text(track.name)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            return
        }

        player.currentTrack = track
        Task {
            guard player.currentTrack == track else { return }

            do {
                try await player.play()
            } catch is CancellationError {
                // Switching tracks or stopping during loading is not a playback error.
            } catch {
                if player.currentTrack == track {
                    onPlaybackError(error)
                }
            }
        }
    }
}

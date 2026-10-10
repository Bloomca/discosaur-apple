import Foundation
import SwiftUI

struct TrackRow: View {
    let playlist: Playlist
    let index: Int
    let player: Player

    private var track: Track { playlist.tracks[index] }
    private var isCurrentTrack: Bool {
        player.activePlaylist?.id == playlist.id && player.currentIndex == index
    }

    @State private var isHovered = false
    @FocusState private var isPlaybackFocused: Bool

    private var isPlaying: Bool {
        isCurrentTrack && player.status == .playing
    }

    private var isLoading: Bool {
        isCurrentTrack && player.isLoading
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

        player.selectTrack(in: playlist, at: index)
        Task {
            guard isCurrentTrack else { return }
            // Playback errors are exposed by Player and presented in the player bar.
            try? await player.play()
        }
    }
}

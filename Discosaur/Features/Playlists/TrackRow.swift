import Foundation
import SwiftUI

struct TrackRow: View {
    let playlist: Playlist
    let index: Int
    let player: Player
    let onPlay: (Playlist.ID, Track.ID) -> Void
    let onDelete: (Playlist.ID, Track.ID) -> Void
    let onOpenInFinder: (Playlist.ID, Track.ID) -> Void

    private var track: Track { playlist.tracks[index] }
    private var subtitle: String {
        [track.artist, track.album?.title].compactMap { $0 }.joined(separator: " • ")
    }

    private var isCurrentTrack: Bool {
        player.activePlaylist?.id == playlist.id && player.currentTrack?.id == track.id
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
        isHovered || isLoading || isPlaybackFocused
        #else
        true
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
                    .padding(1)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .focused($isPlaybackFocused)
            .disabled(isLoading)
            .opacity(showsPlaybackControl ? 1 : 0)
            .help(isPlaying ? "Pause" : "Play")
            .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(track.name)")
            .accessibilityIdentifier("playback-\(track.url.absoluteString)")

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .lineLimit(1)
                    .help(track.fileName)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(track.duration.map(PlaybackTime.format) ?? "---")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("Duration: \(track.duration.map(PlaybackTime.format) ?? "unknown")")
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .listRowBackground(isCurrentTrack ? Color.accentColor.opacity(0.1) : nil)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: playTrack)
                .disabled(isLoading)
                .accessibilityIdentifier("playTrackMenuItem")
            #if os(macOS)
            Button("Open in Finder", systemImage: "folder") {
                onOpenInFinder(playlist.id, track.id)
            }
            .accessibilityIdentifier("openInFinderMenuItem")
            #endif
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete(playlist.id, track.id)
            }
            .accessibilityIdentifier("deleteTrackMenuItem")
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            return
        }

        playTrack()
    }

    private func playTrack() {
        guard !isLoading else { return }
        onPlay(playlist.id, track.id)
    }
}

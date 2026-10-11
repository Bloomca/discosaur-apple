#if os(iOS)
import SwiftUI

// This bar belongs to the navigation shell, not to the browsed playlist.
struct MiniPlayerView: View {
    let player: Player
    let artworkCache: AlbumArtworkCache

    private var isPlaying: Bool { player.status == .playing }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    trackSummary
                    transportControls
                }
                progressControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing")
        .accessibilityIdentifier("miniPlayerView")
        .task(id: player.currentTrack?.album?.coverLocation) {
            await artworkCache.load(player.currentTrack?.album?.coverLocation)
        }
    }

    private var trackSummary: some View {
        HStack(spacing: 12) {
            if let data = artworkCache.data(for: player.currentTrack?.album?.coverLocation) {
                AlbumCoverView(data: data, size: 44)
                    .equatable()
            } else {
                Image(systemName: "music.note")
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTrack?.name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("miniPlayerTrackTitle")
                if let artist = player.currentTrack?.artist ?? player.currentTrack?.album?.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            Button {
                performPlayback(player.previous)
            } label: {
                Image(systemName: "backward.end.fill")
                    .frame(width: 44, height: 44)
            }
            .disabled(!player.canGoPrevious)
            .accessibilityLabel("Previous track")
            .accessibilityIdentifier("miniPlayerPrevious")

            Button(action: togglePlayback) {
                if player.isLoading {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("miniPlayerPlayPause")

            Button {
                performPlayback(player.next)
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 44, height: 44)
            }
            .disabled(!player.canGoNext)
            .accessibilityLabel("Next track")
            .accessibilityIdentifier("miniPlayerNext")
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack == nil || player.isLoading)
    }

    private var progressControls: some View {
        HStack(spacing: 8) {
            Text(PlaybackTime.format(player.position))
                .fixedSize()
                .accessibilityLabel("Elapsed time: \(PlaybackTime.format(player.position))")
                .accessibilityIdentifier("miniPlayerElapsedTime")

            // Shared seeking keeps paused playback paused and cancels a scrub
            // when the playing selection changes.
            SeekSlider(player: player)

            Text(player.duration.map(PlaybackTime.format) ?? "---")
                .fixedSize()
                .accessibilityLabel("Duration: \(player.duration.map(PlaybackTime.format) ?? "unknown")")
                .accessibilityIdentifier("miniPlayerDuration")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            performPlayback(player.play)
        }
    }

    private func performPlayback(_ action: @escaping @MainActor () async throws -> Void) {
        guard let playlistID = player.activePlaylist?.id,
              let trackID = player.currentTrack?.id, !player.isLoading else { return }
        Task {
            guard player.activePlaylist?.id == playlistID, player.currentTrack?.id == trackID else { return }
            // The root presents Player errors; cancellation needs no alert.
            try? await action()
        }
    }
}
#endif

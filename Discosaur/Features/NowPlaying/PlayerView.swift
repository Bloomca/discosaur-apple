import Foundation
import SwiftUI

struct PlayerView: View {
    private let player = Player.shared

    private var hasTrack: Bool { player.currentTrack != nil }
    private var isPlaying: Bool { player.status == .playing }

    private var trackDetails: String? {
        guard let track = player.currentTrack else { return nil }
        var details = track.album ?? ""
        if let artist = track.artist ?? track.albumArtist {
            details = details.isEmpty ? artist : "\(details) by \(artist)"
        }
        if let year = track.year {
            details += details.isEmpty ? "(\(year))" : " (\(year))"
        }
        return details.isEmpty ? nil : details
    }

    private var timeLabel: String {
        guard hasTrack else { return "--- / ---" }
        let duration = player.duration.map(PlaybackTime.format) ?? "---"
        return "\(PlaybackTime.format(player.position)) / \(duration)"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.name ?? "No track selected")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(player.currentTrack?.name ?? "No track selected")
                    .accessibilityIdentifier("playerTrackTitle")

                if let trackDetails {
                    Text(trackDetails)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(trackDetails)
                        .accessibilityIdentifier("playerTrackDetails")
                }
            }
            .frame(maxWidth: 220, alignment: .leading)

            VStack(spacing: 4) {
                Text(timeLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playerTime")
                
                SeekSlider(player: player)
            }
            .frame(minWidth: 80, maxWidth: .infinity)

            HStack(spacing: 4) {
                transportButton("Stop", systemImage: "stop.fill", action: player.stop)
                    .accessibilityIdentifier("playerStop")

                transportButton(
                    "Previous track",
                    systemImage: "backward.end.fill",
                    isEnabled: player.canGoPrevious
                ) {
                    performPlayback(player.previous)
                }
                .accessibilityIdentifier("playerPrevious")

                transportButton(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    isEnabled: !player.isLoading,
                    action: togglePlayback
                )
                .accessibilityIdentifier("playerPlayPause")

                transportButton(
                    "Next track",
                    systemImage: "forward.end.fill",
                    isEnabled: player.canGoNext
                ) {
                    performPlayback(player.next)
                }
                .accessibilityIdentifier("playerNext")
            }
            .disabled(!hasTrack)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("playerView")
        .alert("Could not play track", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    player.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    private func transportButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private func togglePlayback() {
        guard let playlist = player.activePlaylist, let index = player.currentIndex else { return }
        if isPlaying {
            player.pause()
            return
        }

        performPlayback {
            guard player.activePlaylist?.id == playlist.id, player.currentIndex == index else { return }
            try await player.play()
        }
    }

    private func performPlayback(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            // Player publishes failures through errorMessage; cancellation needs no alert.
            try? await action()
        }
    }
}

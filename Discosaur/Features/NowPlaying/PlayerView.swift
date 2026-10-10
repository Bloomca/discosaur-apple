import Foundation
import SwiftUI

struct PlayerView: View {
    private let player = Player.shared
    @State private var playbackError: String?

    private var hasTrack: Bool { player.currentTrack != nil }
    private var isPlaying: Bool { player.status == .playing }

    private var timeLabel: String {
        guard hasTrack else { return "--- / ---" }
        let duration = player.duration.map(formatTime) ?? "---"
        return "\(formatTime(player.position)) / \(duration)"
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

                Text(timeLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playerTime")
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                transportButton("Stop", systemImage: "stop.fill", action: player.stop)
                    .accessibilityIdentifier("playerStop")

                transportButton("Previous track", systemImage: "backward.end.fill", isEnabled: false) {}
                    .accessibilityIdentifier("playerPrevious")

                transportButton(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    isEnabled: !player.isLoading,
                    action: togglePlayback
                )
                .accessibilityIdentifier("playerPlayPause")

                transportButton("Next track", systemImage: "forward.end.fill", isEnabled: false) {}
                    .accessibilityIdentifier("playerNext")
            }
            .disabled(!hasTrack)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("playerView")
        .alert("Could not play track", isPresented: Binding(
            get: { playbackError != nil },
            set: { isPresented in
                if !isPresented {
                    playbackError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
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
        guard let track = player.currentTrack else { return }
        if isPlaying {
            player.pause()
            return
        }

        Task {
            guard player.currentTrack == track else { return }

            do {
                try await player.play()
            } catch is CancellationError {
                // A stopped or replaced track does not need an error alert.
            } catch {
                if player.currentTrack == track {
                    playbackError = error.localizedDescription
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0, time < Double(Int.max) else { return "---" }

        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = String(format: "%02d", totalSeconds % 60)

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(seconds)"
        }
        return "\(minutes):\(seconds)"
    }
}

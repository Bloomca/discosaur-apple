#if os(iOS)
import SwiftUI

// This is a navigation-level bar a not specific to a view
struct MiniPlayerView: View {
    let player: Player
    let artworkCache: AlbumArtworkCache

    private var isPlaying: Bool { player.status == .playing }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
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
                    if let artist = player.currentTrack?.artist ?? player.currentTrack?.album?.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: togglePlayback) {
                    if player.isLoading {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                    }
                }
                .disabled(player.isLoading)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("miniPlayerPlayPause")

                Button {
                    Task { try? await player.next() }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(!player.canGoNext || player.isLoading)
                .accessibilityLabel("Next track")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityIdentifier("miniPlayerView")
        .task(id: player.currentTrack?.album?.coverLocation) {
            await artworkCache.load(player.currentTrack?.album?.coverLocation)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            Task { try? await player.play() }
        }
    }
}
#endif

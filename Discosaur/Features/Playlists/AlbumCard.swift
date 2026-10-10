import SwiftUI

struct AlbumCard: View {
    let album: AlbumGroup
    let playlist: Playlist
    let player: Player

    @State private var isHovered = false
    @FocusState private var isPlaybackFocused: Bool

    private var isCurrentAlbum: Bool {
        guard player.activePlaylist?.id == playlist.id, let index = player.currentIndex else { return false }
        return album.trackIndices.contains(index)
    }

    private var isPlaying: Bool { isCurrentAlbum && player.status == .playing }
    private var isLoading: Bool { isCurrentAlbum && player.isLoading }

    private var showsPlaybackControl: Bool {
        #if os(macOS)
        isHovered || isPlaybackFocused || isLoading
        #else
        true
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(.quaternary)

                if let data = album.coverData {
                    GeometryReader { geometry in
                        AlbumCoverView(data: data, size: geometry.size.width)
                            .equatable()
                            .accessibilityHidden(true)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text(album.title)
                            .font(.headline)
                            .lineLimit(3)
                        Text(album.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .accessibilityHidden(true)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                playbackButton
                    .padding(12)
            }

            Text(album.title)
                .font(.headline)
                .lineLimit(1)
                .help(album.title)
            Text(album.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(album.artist)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("albumCard")
    }

    private var playbackButton: some View {
        Button(action: togglePlayback) {
            ZStack {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 24, height: 24)
            .padding(6)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .focused($isPlaybackFocused)
        .disabled(isLoading)
        .opacity(showsPlaybackControl ? 1 : 0)
        .help(isPlaying ? "Pause album" : "Play album")
        .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(album.title) by \(album.artist)")
        .accessibilityIdentifier("albumPlayback")
    }

    private func togglePlayback() {
        guard !isLoading else { return }
        if isPlaying {
            player.pause()
            return
        }

        if !isCurrentAlbum || player.status != .paused {
            player.selectAlbum(in: playlist, id: album.id)
        }
        guard let selectedTrackID = player.currentTrack?.id else { return }
        Task {
            guard player.activePlaylist?.id == playlist.id,
                  player.currentTrack?.id == selectedTrackID else { return }
            // Playback errors are presented by the player bar, just as in list mode.
            try? await player.play()
        }
    }
}

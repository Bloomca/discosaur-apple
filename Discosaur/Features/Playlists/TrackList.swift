import SwiftUI

struct TrackList: View {
    let playlist: Playlist?
    let player: Player

    var body: some View {
        List {
            if let playlist {
                ForEach(playlist.tracks.enumerated(), id: \.element.id) { entry in
                    TrackRow(playlist: playlist, index: entry.offset, player: player)
                }
            }
        }
        .overlay {
            if playlist?.tracks.isEmpty != false {
                Text("No tracks yet")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("trackList")
    }
}

import SwiftUI

struct TrackList: View {
    let tracks: [Track]

    var body: some View {
        List(tracks) { track in
            Text(track.name)
                .textSelection(.enabled)
        }
        .overlay {
            if tracks.isEmpty {
                Text("No tracks yet")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("trackList")
    }
}

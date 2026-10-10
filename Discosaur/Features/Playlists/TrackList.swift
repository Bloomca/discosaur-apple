import Foundation
import SwiftUI

struct TrackList: View {
    let tracks: [Track]

    private let player = Player.shared
    @State private var playbackError: String?

    var body: some View {
        List(tracks) { track in
            TrackRow(track: track, player: player) { error in
                playbackError = error.localizedDescription
            }
        }
        .overlay {
            if tracks.isEmpty {
                Text("No tracks yet")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("trackList")
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
}

import SwiftUI

struct AlbumGallery: View {
    let playlist: Playlist?
    let player: Player
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                if let playlist {
                    ForEach(playlist.albumGroups) { album in
                        AlbumCard(album: album, playlist: playlist, player: player)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if playlist?.tracks.isEmpty != false {
                Text("No albums yet")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("albumGallery")
    }
}

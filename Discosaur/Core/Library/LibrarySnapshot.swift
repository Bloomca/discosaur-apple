import Foundation

// Durable library contents only. Browsing selection and playback are separate state in userDefaults
nonisolated struct LibrarySnapshot: Equatable, Sendable {
    let playlists: [Playlist]
    let sources: [FileSource]

    init(playlists: [Playlist] = [], sources: [FileSource] = []) {
        self.playlists = playlists
        self.sources = sources
    }
}

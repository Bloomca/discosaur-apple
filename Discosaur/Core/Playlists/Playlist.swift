import Foundation

nonisolated struct Playlist: Identifiable, Equatable, Sendable {
    let id = UUID()
    let tracks: [Track]
}

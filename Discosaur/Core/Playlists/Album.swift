import Foundation

nonisolated struct Album: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String?
    let artist: String?
    let year: Int?
    let coverData: Data?
}

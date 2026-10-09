import Foundation

nonisolated struct Track: Identifiable, Equatable, Sendable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL) {
        self.url = url.standardizedFileURL
    }
}

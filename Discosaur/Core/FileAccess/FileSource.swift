import Foundation

nonisolated struct FileSource: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case file
        case folder
    }

    let id: UUID
    let kind: Kind
    var bookmarkData: Data

    init(id: UUID = UUID(), kind: Kind, bookmarkData: Data) {
        self.id = id
        self.kind = kind
        self.bookmarkData = bookmarkData
    }
}

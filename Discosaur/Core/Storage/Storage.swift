import Foundation

nonisolated protocol LibraryStoring: Sendable {
    func load() async throws -> LibrarySnapshot?
    func save(_ snapshot: LibrarySnapshot) async throws
}

// Disk work runs off the main actor. No suspension inside reads/writes means a
// document is validated, encoded, and atomically replaced as one serialized operation.
actor Storage: LibraryStoring {
    nonisolated let fileURL: URL

    nonisolated static var defaultLibraryURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Discosaur", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    init(fileURL: URL = Storage.defaultLibraryURL) {
        self.fileURL = fileURL
    }

    func load() throws -> LibrarySnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        // Inspect the version before decoding its payload, so a future schema is
        // reported as unsupported rather than mistaken for a damaged v1 document.
        let header = try decoder.decode(Header.self, from: data)
        guard header.version == 1 else { throw StorageError.unsupportedVersion(header.version) }
        return try decoder.decode(LibraryDocumentV1.self, from: data).snapshot()
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(LibraryDocumentV1(snapshot: snapshot))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private struct Header: Decodable {
        let version: Int
    }
}

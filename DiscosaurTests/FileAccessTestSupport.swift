import Foundation
@testable import Discosaur

@MainActor
final class TestFileAccessBackend: FileAccessBackend {
    enum Failure: Error {
        case bookmarkCreation
        case bookmarkResolution
    }

    var startsSucceed = true
    var failsBookmarkCreation = false
    var failsResolution = false
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []
    private(set) var bookmarkedURLs: [URL] = []
    private var bookmarks: [Data: (url: URL, isStale: Bool)] = [:]

    func registerBookmark(for url: URL, isStale: Bool = false) -> Data {
        let data = Data(UUID().uuidString.utf8)
        bookmarks[data] = (url, isStale)
        return data
    }

    func bookmarkData(for url: URL) throws -> Data {
        if failsBookmarkCreation { throw Failure.bookmarkCreation }
        bookmarkedURLs.append(url)
        return registerBookmark(for: url)
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard !failsResolution, let resolved = bookmarks[data] else {
            throw Failure.bookmarkResolution
        }
        return resolved
    }

    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)
        return startsSucceed
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
    }
}

struct FileAccessFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileAccessTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func folder(_ relativePath: String) throws -> URL {
        let url = directory.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ relativePath: String) throws -> URL {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

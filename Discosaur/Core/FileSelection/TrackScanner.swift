import Foundation
import UniformTypeIdentifiers

nonisolated struct TrackScanner: Sendable {
    // Supported audio data
    private static let audioExtensions: Set<String> = [
        "aac", "aif", "aiff", "aifc", "caf", "flac", "m4a", "m4b",
        "mp3", "oga", "ogg", "opus", "wav", "wave",
    ]

    static var audioContentTypes: [UTType] {
        [.audio] + audioExtensions.sorted().compactMap {
            UTType(filenameExtension: $0, conformingTo: .audio)
        }
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .contentTypeKey,
    ]

    @concurrent
    func tracks(from urls: [URL]) async throws -> [Track] {
        try scan(urls)
    }

    private func scan(_ urls: [URL]) throws -> [Track] {
        let fileManager = FileManager()
        var tracks: [Track] = []
        var seen: Set<URL> = []

        for url in urls {
            try Task.checkCancellation()

            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let resources = try url.resourceValues(forKeys: Self.resourceKeys)
            if resources.isDirectory == true {
                var enumerationError: Error?
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: Array(Self.resourceKeys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, error in
                        enumerationError = error
                        return false
                    }
                ) else {
                    throw SelectionError.unreadableFolder(url)
                }

                for case let fileURL as URL in enumerator {
                    try Task.checkCancellation()
                    try appendTrack(at: fileURL, to: &tracks, seen: &seen)
                }

                if let enumerationError {
                    throw enumerationError
                }
            } else {
                try appendTrack(at: url, to: &tracks, seen: &seen)
            }
        }

        return tracks.sorted { left, right in
            let order = left.fileName.localizedStandardCompare(right.fileName)
            if order == .orderedSame {
                return left.url.path < right.url.path
            }
            return order == .orderedAscending
        }
    }

    private func appendTrack(at url: URL, to tracks: inout [Track], seen: inout Set<URL>) throws {
        let resources = try url.resourceValues(forKeys: Self.resourceKeys)
        guard resources.isRegularFile == true else { return }

        let isAudio = resources.contentType?.conforms(to: .audio) == true
            || Self.audioExtensions.contains(url.pathExtension.lowercased())
        guard isAudio else { return }

        let track = Track(url: url)
        if seen.insert(track.url).inserted {
            tracks.append(track)
        }
    }

    private enum SelectionError: LocalizedError {
        case unreadableFolder(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableFolder(let url):
                return "The folder ‘\(url.lastPathComponent)’ could not be read."
            }
        }
    }
}

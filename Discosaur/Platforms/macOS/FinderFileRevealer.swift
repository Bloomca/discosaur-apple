#if os(macOS)
import AppKit

@MainActor
struct FinderFileRevealer {
    private let fileAccessManager: FileAccessManager
    private let revealURLs: ([URL]) -> Void

    init(
        fileAccessManager: FileAccessManager,
        revealURLs: @escaping ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    ) {
        self.fileAccessManager = fileAccessManager
        self.revealURLs = revealURLs
    }

    func reveal(_ track: Track) throws {
        let access: ScopedFileAccess
        if let location = track.location {
            access = try fileAccessManager.acquire(location)
        } else {
            access = try fileAccessManager.acquireLocalFile(at: track.url)
        }
        defer { access.close() }

        // Validate the resolved URL while scoped access is active, not the import URL.
        let url = access.resourceURL
        guard try url.checkResourceIsReachable() else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        revealURLs([url])
    }
}
#endif

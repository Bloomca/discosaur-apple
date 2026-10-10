import Foundation

@MainActor
final class FileAccessManager {
    private struct ActiveScope {
        var source: FileSource
        let rootURL: URL
        let didStartAccess: Bool
        var users: Int
    }

    private let library: Library
    private let backend: any FileAccessBackend
    private var activeScopes: [UUID: ActiveScope] = [:]

    init(library: Library, backend: (any FileAccessBackend)? = nil) {
        self.library = library
        self.backend = backend ?? SystemFileAccessBackend()
    }

    // The caller holds this lease through scanning and metadata reads, and commits
    // the source to the library only if the import succeeds and uses it.
    func prepareSource(for selectedURL: URL) throws -> (source: FileSource, access: ScopedFileAccess) {
        guard selectedURL.isFileURL else { throw FileAccessError.localFileRequired }
        let didStartAccess = backend.startAccessing(selectedURL)
        var transfersAccess = false
        defer {
            if didStartAccess, !transfersAccess {
                backend.stopAccessing(selectedURL)
            }
        }

        let resources = try selectedURL.resourceValues(forKeys: [.isDirectoryKey])
        let kind: FileSource.Kind = resources.isDirectory == true ? .folder : .file
        let source = FileSource(
            id: matchingSourceID(for: selectedURL, kind: kind) ?? UUID(),
            kind: kind,
            bookmarkData: try backend.bookmarkData(for: selectedURL)
        )

        if var active = activeScopes[source.id] {
            active.source = source
            active.users += 1
            activeScopes[source.id] = active
            return (source, lease(for: source.id, resourceURL: active.rootURL))
        }

        activeScopes[source.id] = ActiveScope(
            source: source,
            rootURL: selectedURL,
            didStartAccess: didStartAccess,
            users: 1
        )
        transfersAccess = true
        return (source, lease(for: source.id, resourceURL: selectedURL))
    }

    func acquire(_ location: FileLocation) throws -> ScopedFileAccess {
        guard let source = library.source(id: location.sourceID) else {
            throw FileAccessError.unknownSource(location.sourceID)
        }
        let rootURL = try retainScope(for: source)
        do {
            let resourceURL = try location.resourceURL(relativeTo: rootURL, kind: source.kind)
            return lease(for: source.id, resourceURL: resourceURL)
        } catch {
            releaseScope(for: source.id)
            throw error
        }
    }

    // Legacy/app-owned tracks may not have a source. A false start result is not
    // itself an error: container files need no grant, and the actual read reports
    // denied access. Only successful starts must be balanced with a stop.
    func acquireLocalFile(at url: URL) throws -> ScopedFileAccess {
        guard url.isFileURL else { throw FileAccessError.localFileRequired }
        let didStartAccess = backend.startAccessing(url)
        return ScopedFileAccess(resourceURL: url) { [backend] in
            if didStartAccess {
                backend.stopAccessing(url)
            }
        }
    }

    private func retainScope(for source: FileSource) throws -> URL {
        if var active = activeScopes[source.id] {
            active.users += 1
            activeScopes[source.id] = active
            return active.rootURL
        }

        let resolved = try backend.resolveBookmark(source.bookmarkData)
        guard resolved.url.isFileURL else { throw FileAccessError.localFileRequired }
        let didStartAccess = backend.startAccessing(resolved.url)
        var keepsAccess = false
        defer {
            if didStartAccess, !keepsAccess {
                backend.stopAccessing(resolved.url)
            }
        }

        var refreshed = source
        if resolved.isStale {
            refreshed.bookmarkData = try backend.bookmarkData(for: resolved.url)
            library.updateSource(refreshed)
        }
        activeScopes[source.id] = ActiveScope(
            source: refreshed,
            rootURL: resolved.url,
            didStartAccess: didStartAccess,
            users: 1
        )
        keepsAccess = true
        return resolved.url
    }

    private func matchingSourceID(for url: URL, kind: FileSource.Kind) -> UUID? {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        // Also reuse sources staged by another import that has not committed yet.
        for active in activeScopes.values where active.source.kind == kind {
            if active.rootURL.standardizedFileURL.resolvingSymlinksInPath() == canonicalURL {
                return active.source.id
            }
        }
        for source in library.sources where source.kind == kind {
            guard let resolved = try? backend.resolveBookmark(source.bookmarkData),
                  resolved.url.standardizedFileURL.resolvingSymlinksInPath() == canonicalURL else { continue }
            return source.id
        }
        return nil
    }

    private func lease(for sourceID: UUID, resourceURL: URL) -> ScopedFileAccess {
        ScopedFileAccess(resourceURL: resourceURL) {
            self.releaseScope(for: sourceID)
        }
    }

    private func releaseScope(for sourceID: UUID) {
        guard var active = activeScopes[sourceID] else { return }
        active.users -= 1
        if active.users == 0 {
            activeScopes.removeValue(forKey: sourceID)
            if active.didStartAccess {
                backend.stopAccessing(active.rootURL)
            }
        } else {
            activeScopes[sourceID] = active
        }
    }
}

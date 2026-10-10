import Foundation

// Keep system bookmark/scope calls injectable so lifecycle and stale-bookmark
// handling can be tested without relying on the sandbox's current permissions.
@MainActor
protocol FileAccessBackend {
    func bookmarkData(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

@MainActor
struct SystemFileAccessBackend: FileAccessBackend {
    func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        return try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

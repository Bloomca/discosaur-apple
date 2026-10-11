import Foundation

@MainActor
protocol LibraryStateStoring {
    func load() -> LibraryState
    func save(_ state: LibraryState)
}

@MainActor
struct LibraryStateStorage: LibraryStateStoring {
    static let key = "libraryState"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LibraryState {
        let values = defaults.dictionary(forKey: Self.key) ?? [:]
        let selectedPlaylistID = (values["selectedPlaylistID"] as? String).flatMap(UUID.init(uuidString:))
        let activePlaylistID = (values["activePlaylistID"] as? String).flatMap(UUID.init(uuidString:))
        let url = (values["currentTrackID"] as? String).flatMap(URL.init(string:))
        return LibraryState(
            selectedPlaylistID: selectedPlaylistID,
            activePlaylistID: activePlaylistID,
            currentTrackID: url.flatMap { $0.isFileURL ? $0.standardizedFileURL : nil }
        )
    }

    func save(_ state: LibraryState) {
        // One property-list dictionary keeps the playback pair together. Missing
        // optional values remove old references instead of leaving stale keys behind.
        var values: [String: String] = [:]
        if let id = state.selectedPlaylistID { values["selectedPlaylistID"] = id.uuidString }
        if let id = state.activePlaylistID { values["activePlaylistID"] = id.uuidString }
        if let id = state.currentTrackID { values["currentTrackID"] = id.absoluteString }
        if values.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(values, forKey: Self.key)
        }
    }
}

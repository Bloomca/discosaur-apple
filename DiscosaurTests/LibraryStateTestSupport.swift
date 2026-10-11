import Foundation
import Testing
@testable import Discosaur

@MainActor
struct StateDefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "com.bloomca.Discosaur.state-tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
final class StateTestStorage: LibraryStateStoring {
    private(set) var loadCount = 0
    private(set) var savedStates: [LibraryState] = []
    private var state: LibraryState

    init(state: LibraryState = LibraryState()) {
        self.state = state
    }

    func load() -> LibraryState {
        loadCount += 1
        return state
    }

    func save(_ state: LibraryState) {
        self.state = state
        savedStates.append(state)
    }
}

@MainActor
final class StateTestEngine: FilePlaybackEngine {
    var position: TimeInterval = 0
    var volume: Float = 1
    var onPlaybackEnded: (@MainActor () -> Void)?
    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0

    func loadFile(at url: URL) async throws -> AudioFileInfo {
        loadedURLs.append(url)
        return AudioFileInfo(duration: 60)
    }

    func play() throws { playCount += 1 }
    func pause() {}
    func stop() { position = 0 }
    func seek(to position: TimeInterval) throws { self.position = position }
}

actor StateTestLibraryStorage: LibraryStoring {
    enum Failure: Error { case load }
    private let snapshot: LibrarySnapshot
    private(set) var savedSnapshots: [LibrarySnapshot] = []
    private var failsLoading = false
    private var suspendsLoading = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: LibrarySnapshot, suspendsLoading: Bool = false, failsLoading: Bool = false) {
        self.snapshot = snapshot
        self.suspendsLoading = suspendsLoading
        self.failsLoading = failsLoading
    }

    func load() async throws -> LibrarySnapshot? {
        if suspendsLoading {
            suspendsLoading = false
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        if failsLoading { throw Failure.load }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) {
        savedSnapshots.append(snapshot)
    }

    func setFailsLoading(_ fails: Bool) { failsLoading = fails }

    func waitUntilLoading() async {
        guard loadContinuation == nil else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeLoading() {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class LibraryPersistence {
    enum Status { case idle, loading, ready, failed }

    private(set) var status: Status = .idle
    private(set) var hasUnsavedChanges = false
    var errorMessage: String?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let storage: any LibraryStoring
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var savedRevision: UInt64 = 0

    init(library: Library, storage: any LibraryStoring, autosaveDelay: Duration = .milliseconds(250)) {
        self.library = library
        self.storage = storage
        self.autosaveDelay = autosaveDelay
        library.onChange = { [weak self] in self?.scheduleSave() }
    }

    isolated deinit {
        debounceTask?.cancel()
    }

    // Shared by all windows. A cancelled view task does not interrupt startup IO.
    func loadIfNeeded() async {
        guard status == .idle else { return }
        status = .loading
        errorMessage = nil
        do {
            if let snapshot = try await storage.load() {
                library.restore(snapshot)
            }
            status = .ready
        } catch {
            // Never autosave an empty/partial library after a failed load.
            status = .failed
            errorMessage = error.localizedDescription
        }
    }

    func retryLoad() async {
        guard status == .failed else { return }
        status = .idle
        await loadIfNeeded()
    }

    // Used by Retry, backgrounding, and orderly quit. Reads the latest contents,
    // even if a previous save is still in flight or debounce has not elapsed.
    func flush() async {
        guard status == .ready else { return }
        debounceTask?.cancel()
        debounceTask = nil
        startWriting()
        await writeTask?.value
    }

    private func scheduleSave() {
        guard status == .ready else { return }
        revision &+= 1
        hasUnsavedChanges = true
        debounceTask?.cancel()
        debounceTask = Task { [weak self, autosaveDelay] in
            do {
                try await Task.sleep(for: autosaveDelay)
            } catch {
                return
            }
            self?.startWriting()
        }
    }

    private func startWriting() {
        guard writeTask == nil, revision != savedRevision else { return }
        writeTask = Task { [weak self] in
            await self?.writeChanges()
        }
    }

    private func writeChanges() async {
        defer { writeTask = nil }
        // One writer, regardless of storage implementation or actor scheduling.
        // Edits made during a save are written afterwards, never overwritten by it.
        while revision != savedRevision {
            let savingRevision = revision
            let snapshot = library.snapshot
            do {
                try await storage.save(snapshot)
                savedRevision = savingRevision
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                return // Keep dirty state; retry on the next edit or explicit flush.
            }
        }
        hasUnsavedChanges = false
    }
}

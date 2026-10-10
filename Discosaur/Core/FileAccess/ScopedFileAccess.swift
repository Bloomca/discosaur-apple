import Foundation

@MainActor
final class ScopedFileAccess {
    let resourceURL: URL
    private var onClose: (() -> Void)?

    init(resourceURL: URL, onClose: @escaping () -> Void) {
        self.resourceURL = resourceURL
        self.onClose = onClose
    }

    // Explicit close gives callers control over ordering (close the audio file
    // before releasing its scope). Deinitialization is a safety net.
    func close() {
        let action = onClose
        onClose = nil
        action?()
    }

    isolated deinit {
        close()
    }
}

import Foundation

nonisolated enum StorageError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidLibrary(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Library format version \(version) is not supported by this version of Discosaur."
        case .invalidLibrary(let reason):
            return "The library is invalid: \(reason)"
        }
    }
}

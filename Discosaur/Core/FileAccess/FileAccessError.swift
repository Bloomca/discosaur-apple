import Foundation

nonisolated enum FileAccessError: LocalizedError {
    case localFileRequired
    case unknownSource(UUID)
    case sourceKindMismatch
    case invalidRelativePath(String)
    case outsideSource(URL)

    var errorDescription: String? {
        switch self {
        case .localFileRequired:
            return "Only local files and folders can be accessed."
        case .unknownSource:
            return "The file source is no longer available. Please select the file or folder again."
        case .sourceKindMismatch:
            return "The file location does not match its selected file or folder."
        case .invalidRelativePath:
            return "The track has an invalid path within its selected folder."
        case .outsideSource(let url):
            return "The file ‘\(url.lastPathComponent)’ is outside the selected folder."
        }
    }
}

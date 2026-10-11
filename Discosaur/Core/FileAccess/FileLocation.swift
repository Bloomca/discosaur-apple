import Foundation

nonisolated enum FileLocation: Codable, Hashable, Sendable {
    case selectedFile(sourceID: UUID)
    case insideFolder(sourceID: UUID, relativePath: String)

    private enum CodingKeys: String, CodingKey {
        case kind, sourceID, relativePath
    }

    private enum Kind: String, Codable {
        case selectedFile, insideFolder
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sourceID = try values.decode(UUID.self, forKey: .sourceID)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .selectedFile:
            self = .selectedFile(sourceID: sourceID)
        case .insideFolder:
            self = .insideFolder(
                sourceID: sourceID,
                relativePath: try values.decode(String.self, forKey: .relativePath)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sourceID, forKey: .sourceID)
        switch self {
        case .selectedFile:
            try values.encode(Kind.selectedFile, forKey: .kind)
        case .insideFolder(_, let relativePath):
            try values.encode(Kind.insideFolder, forKey: .kind)
            try values.encode(relativePath, forKey: .relativePath)
        }
    }

    var sourceID: UUID {
        switch self {
        case .selectedFile(let sourceID), .insideFolder(let sourceID, _):
            return sourceID
        }
    }

    func resourceURL(relativeTo root: URL, kind: FileSource.Kind) throws -> URL {
        guard root.isFileURL else { throw FileAccessError.localFileRequired }
        switch self {
        case .selectedFile:
            guard kind == .file else { throw FileAccessError.sourceKindMismatch }
            return root
        case .insideFolder(_, let relativePath):
            guard kind == .folder else { throw FileAccessError.sourceKindMismatch }
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw FileAccessError.invalidRelativePath(relativePath)
            }
            let url = root.appendingPathComponent(relativePath).standardizedFileURL
            guard Self.relativePath(of: url, inside: root) != nil else {
                throw FileAccessError.outsideSource(url)
            }
            return url
        }
    }

    // Component-based, symlink-aware containment avoids both sibling-prefix matches
    // (Album vs Album Other) and links that lead outside the authorized folder.
    static func relativePath(of url: URL, inside folder: URL) -> String? {
        guard url.isFileURL, folder.isFileURL else { return nil }
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let child = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard child.count > root.count, child.starts(with: root) else { return nil }
        return child.dropFirst(root.count).joined(separator: "/")
    }
}

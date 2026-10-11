import Foundation

// Production uses Application Support and standard defaults. Debug test launches
// share one isolation ID for their sandbox-local file and private defaults suite.
nonisolated enum LibraryStorageLocation {
    private static let isolationID: UUID? = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let id = environment["DISCOSAUR_TEST_LIBRARY_ID"].flatMap(UUID.init(uuidString:)) {
            return id
        }
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return UUID()
        }
        #endif
        return nil
    }()

    static var current: URL {
        isolationID.map(testURL(id:)) ?? Storage.defaultLibraryURL
    }

    static var userDefaults: UserDefaults {
        guard let id = isolationID else { return .standard }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bloomca.Discosaur"
        guard let defaults = UserDefaults(suiteName: "\(bundleID).tests.\(id.uuidString)") else {
            preconditionFailure("Could not create isolated test defaults.")
        }
        return defaults
    }

    private static func testURL(id: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscosaurTests/\(id.uuidString)", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}

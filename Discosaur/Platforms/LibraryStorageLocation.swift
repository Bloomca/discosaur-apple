import Foundation

// Production uses Application Support. Debug test launches get a sandbox-local,
// isolated file, with a stable test ID allowing relaunch/persistence UI tests.
nonisolated enum LibraryStorageLocation {
    static var current: URL {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let testID = environment["DISCOSAUR_TEST_LIBRARY_ID"].flatMap(UUID.init(uuidString:))
        let isTestHost = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if let testID {
            return testURL(id: testID)
        }
        if isTestHost {
            return testURL(id: UUID())
        }
        #endif
        return Storage.defaultLibraryURL
    }

    private static func testURL(id: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscosaurTests/\(id.uuidString)", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}

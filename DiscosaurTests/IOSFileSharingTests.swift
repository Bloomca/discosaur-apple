#if os(iOS)
import Foundation
import Testing
@testable import Discosaur

@MainActor
struct IOSFileSharingTests {
    @Test func documentsAreSharedWithFinderAndOpenInPlaceInFiles() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool == true)
    }

    @Test func documentsExistAndLibraryMetadataStaysOutsideTheSharedFolder() throws {
        let manager = FileManager.default
        let documents = try #require(manager.urls(for: .documentDirectory, in: .userDomainMask).first)
        var isDirectory: ObjCBool = false
        #expect(manager.fileExists(atPath: documents.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(!Storage.defaultLibraryURL.path.hasPrefix(documents.path + "/"))
    }
}
#endif

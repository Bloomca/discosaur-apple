import Foundation
import Testing
@testable import Discosaur

struct AlbumCodingTests {
    @Test(arguments: [
        FileLocation.selectedFile(sourceID: UUID()),
        FileLocation.insideFolder(sourceID: UUID(), relativePath: "Album/Disc 1/Cover #1.jpg"),
    ])
    func albumRoundTripsWithArtworkReference(location: FileLocation) throws {
        let album = Album(title: "Album", artist: "Artist", year: 2024, coverLocation: location)

        let data = try JSONEncoder().encode(album)
        let decoded = try JSONDecoder().decode(Album.self, from: data)

        #expect(decoded == album)
        #expect(decoded.id == album.id)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["coverData"] == nil)
        let cover = try #require(json["coverLocation"] as? [String: Any])
        #expect(cover["sourceID"] as? String == location.sourceID.uuidString)
        #expect(cover["bookmarkData"] == nil)
        switch location {
        case .selectedFile:
            #expect(cover["kind"] as? String == "selectedFile")
            #expect(cover["relativePath"] == nil)
        case .insideFolder(_, let path):
            #expect(cover["kind"] as? String == "insideFolder")
            #expect(cover["relativePath"] as? String == path)
        }
    }

    @Test func albumWithoutArtworkRoundTrips() throws {
        let album = Album(title: nil, artist: nil, year: nil)
        let data = try JSONEncoder().encode(album)

        #expect(try JSONDecoder().decode(Album.self, from: data) == album)
    }

    @Test func unknownArtworkLocationKindIsRejected() {
        let json = Data("""
            {"kind":"unknown","sourceID":"\(UUID().uuidString)"}
            """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FileLocation.self, from: json)
        }
    }
}

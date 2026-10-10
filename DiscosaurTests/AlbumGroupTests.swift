import Foundation
import Testing
@testable import Discosaur

struct AlbumGroupTests {
    @Test func matchingAlbumsFromSeparateImportsFormOneGroup() throws {
        let first = albumTrack("/Music/Album/01.mp3", title: "Album", artist: "Artist", number: 1)
        let second = albumTrack("/Music/Album/02.mp3", title: "Album", artist: "Artist", number: 2)
        #expect(first.album?.id != second.album?.id)

        let groups = Playlist(tracks: [first, second]).albumGroups

        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.title == "Album")
        #expect(group.artist == "Artist")
        #expect(group.trackIndices == [0, 1])
    }

    @Test func multiDiscAlbumsAreGroupedAndSortedByDiscThenTrack() throws {
        let secondDisc = albumTrack("/Music/Disc 2/01.mp3", title: "Album", artist: "Artist", disc: 2, number: 1)
        let secondTrack = albumTrack("/Music/Disc 1/02.mp3", title: "Album", artist: "Artist", number: 2)
        let firstTrack = albumTrack("/Music/Disc 1/01.mp3", title: "Album", artist: "Artist", number: 1)

        let groups = Playlist(tracks: [secondDisc, secondTrack, firstTrack]).albumGroups

        #expect(groups.count == 1)
        #expect(try #require(groups.first).trackIndices == [2, 1, 0])
    }

    @Test func compilationsUseTheAlbumArtistRatherThanIndividualTrackArtists() throws {
        let first = albumTrack("/Music/Mix/01.mp3", title: "Mix", artist: "Various Artists", trackArtist: "Singer A")
        let second = albumTrack("/Music/Mix/02.mp3", title: "Mix", artist: "Various Artists", trackArtist: "Singer B")

        let groups = Playlist(tracks: [first, second]).albumGroups

        #expect(groups.count == 1)
        #expect(try #require(groups.first).artist == "Various Artists")
    }

    @Test func albumsWithTheSameTitleButDifferentArtistsStaySeparate() {
        let first = albumTrack("/Music/First/01.mp3", title: "Greatest Hits", artist: "Artist A")
        let second = albumTrack("/Music/Second/01.mp3", title: "Greatest Hits", artist: "Artist B")

        let groups = Playlist(tracks: [first, second]).albumGroups

        #expect(groups.count == 2)
        #expect(groups.map(\.artist) == ["Artist A", "Artist B"])
    }

    @Test func unknownAlbumArtistsDoNotMergeUnrelatedFolders() {
        let first = albumTrack("/Music/First/01.mp3", title: "Album", artist: nil)
        let second = albumTrack("/Music/Second/01.mp3", title: "Album", artist: nil)

        #expect(Playlist(tracks: [first, second]).albumGroups.count == 2)
    }

    @Test func untaggedTracksAreGroupedByFolderWithUsefulFallbackLabels() {
        let first = albumTrack("/Music/Collection/01.mp3", title: nil, artist: nil, trackArtist: "Singer A")
        let second = albumTrack("/Music/Collection/02.mp3", title: nil, artist: nil, trackArtist: "Singer B")
        let other = Track(url: URL(fileURLWithPath: "/Music/Other/song.mp3"))

        let groups = Playlist(tracks: [first, second, other]).albumGroups

        #expect(groups.count == 2)
        #expect(groups.map(\.title) == ["Collection", "Other"])
        #expect(groups.map(\.artist) == ["Various artists", "Unknown artist"])
        #expect(groups.map(\.trackIndices) == [[0, 1], [2]])
    }

    @Test func appendedTracksKeepTheAlbumGroupIdentityAndCanSupplyArtwork() throws {
        let first = albumTrack("/Music/Album/01.mp3", title: "Album", artist: "Artist", number: 1)
        let original = Playlist(tracks: [first])
        let originalGroup = try #require(original.albumGroups.first)
        let cover = Data([1, 2, 3])
        let second = albumTrack("/Music/Album/02.mp3", title: "Album", artist: "Artist", number: 2, cover: cover)
        let updated = Playlist(id: original.id, tracks: [first, second])

        let groups = updated.albumGroups

        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.id == originalGroup.id)
        #expect(group.coverData == cover)
        #expect(group.trackIndices == [0, 1])
    }

    @Test func albumAndArtistIdentityIsCaseInsensitive() {
        let first = albumTrack("/Music/Album/01.mp3", title: "ALBUM", artist: "ARTIST")
        let second = albumTrack("/Music/Album/02.mp3", title: "album", artist: "artist")

        #expect(Playlist(tracks: [first, second]).albumGroups.count == 1)
    }

    private func albumTrack(
        _ path: String,
        title: String?,
        artist: String?,
        trackArtist: String? = nil,
        disc: Int = 1,
        number: Int? = nil,
        cover: Data? = nil
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: path),
            metadata: TrackMetadata(artist: trackArtist, album: title, albumArtist: artist, trackNumber: number, discNumber: disc),
            album: title.map { Album(title: $0, artist: artist, year: 2024, coverData: cover) }
        )
    }
}

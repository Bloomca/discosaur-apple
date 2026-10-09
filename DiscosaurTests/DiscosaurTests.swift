//
//  DiscosaurTests.swift
//  DiscosaurTests
//
//  Created by Seva on 10/9/26.
//

import Foundation
import Testing
@testable import Discosaur

struct DiscosaurTests {
    @Test func trackNameIsTheFullFilename() {
        let track = Track(url: URL(fileURLWithPath: "/Music/My Song.flac"))

        #expect(track.name == "My Song.flac")
        #expect(track.id == track.url)
    }

    @Test func playlistPreservesTrackOrder() {
        let tracks = [
            Track(url: URL(fileURLWithPath: "/Music/Second.mp3")),
            Track(url: URL(fileURLWithPath: "/Music/First.mp3")),
        ]

        #expect(Playlist(tracks: tracks).tracks == tracks)
    }
}

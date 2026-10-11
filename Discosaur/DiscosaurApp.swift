//
//  DiscosaurApp.swift
//  Discosaur
//
//  Created by Seva on 10/9/26.
//

import SwiftUI

@main
struct DiscosaurApp: App {
    @State private var library: Library
    @State private var fileAccessManager: FileAccessManager
    @State private var artworkCache: AlbumArtworkCache
    @State private var player: Player

    init() {
        let library = Library()
        let fileAccessManager = FileAccessManager(library: library)
        _library = State(initialValue: library)
        _fileAccessManager = State(initialValue: fileAccessManager)
        _artworkCache = State(initialValue: AlbumArtworkCache(fileAccessManager: fileAccessManager))
        _player = State(initialValue: Player(
            engine: AVFilePlaybackEngine(),
            fileAccessManager: fileAccessManager
        ))
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacRootView(
                library: library,
                fileAccessManager: fileAccessManager,
                artworkCache: artworkCache,
                player: player
            )
            #else
            ContentView()
            #endif
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: true))
        #endif
    }
}

//
//  DiscosaurApp.swift
//  Discosaur
//
//  Created by Seva on 10/9/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct DiscosaurApp: App {
    @State private var library: Library
    @State private var fileAccessManager: FileAccessManager
    @State private var artworkCache: AlbumArtworkCache
    @State private var player: Player
    @State private var persistence: LibraryPersistence
    #if os(iOS)
    @State private var nowPlaying: NowPlayingCoordinator
    #endif
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    #endif

    init() {
        let library = Library()
        let fileAccessManager = FileAccessManager(library: library)
        let player = Player(engine: AVFilePlaybackEngine(), fileAccessManager: fileAccessManager)
        let statePersistence = LibraryStatePersistence(
            library: library,
            player: player,
            storage: LibraryStateStorage(defaults: LibraryStorageLocation.userDefaults)
        )
        let persistence = LibraryPersistence(
            library: library,
            storage: Storage(fileURL: LibraryStorageLocation.current),
            statePersistence: statePersistence
        )
        _persistence = State(initialValue: persistence)
        _library = State(initialValue: library)
        _fileAccessManager = State(initialValue: fileAccessManager)
        let artworkCache = AlbumArtworkCache(fileAccessManager: fileAccessManager)
        _artworkCache = State(initialValue: artworkCache)
        _player = State(initialValue: player)
        #if os(iOS)
        _nowPlaying = State(initialValue: NowPlayingCoordinator(player: player, artworkCache: artworkCache))
        #endif
        #if os(macOS)
        lifecycle.persistence = persistence
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .task {
                    #if DEBUG && os(iOS)
                    await IOSPlaybackTestFixture.prepareIfRequested()
                    #endif
                    await persistence.loadIfNeeded()
                }
                .alert("Could not save library", isPresented: Binding(
                    get: { persistence.status == .ready && persistence.errorMessage != nil },
                    set: { if !$0 { persistence.errorMessage = nil } }
                )) {
                    Button("Retry") { Task { await persistence.flush() } }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(persistence.errorMessage ?? "")
                }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: true))
        #endif
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            player.setProgressUpdatesEnabled(phase == .active)
            nowPlaying.refresh()
            #endif
            if phase == .background {
                Task {
                    #if os(iOS)
                    let taskID = UIApplication.shared.beginBackgroundTask(withName: "Save library")
                    defer {
                        if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
                    }
                    #endif
                    await persistence.flush()
                }
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch persistence.status {
        case .idle, .loading:
            ProgressView("Loading library…")
                .padding(40)
        case .failed:
            ContentUnavailableView {
                Label("Could not load library", systemImage: "exclamationmark.triangle")
            } description: {
                Text((persistence.errorMessage ?? "") + "\n\nThe existing library file has not been changed.")
            } actions: {
                Button("Retry") { Task { await persistence.retryLoad() } }
            }
        case .ready:
            #if os(macOS)
            MacRootView(
                library: library,
                fileAccessManager: fileAccessManager,
                artworkCache: artworkCache,
                player: player
            )
            #elseif os(iOS)
            IOSRootView(
                library: library,
                fileAccessManager: fileAccessManager,
                artworkCache: artworkCache,
                player: player
            )
            #endif
        }
    }
}

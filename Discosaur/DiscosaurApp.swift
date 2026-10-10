//
//  DiscosaurApp.swift
//  Discosaur
//
//  Created by Seva on 10/9/26.
//

import SwiftUI

@main
struct DiscosaurApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacRootView()
            #else
            ContentView()
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        #endif
    }
}

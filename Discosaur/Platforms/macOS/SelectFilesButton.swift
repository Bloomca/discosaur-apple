#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SelectFilesButton: View {
    let onSelect: ([URL]) -> Void
    @State private var isPresentingPicker = false

    var body: some View {
        Button("Open files", action: selectFiles)
            .disabled(isPresentingPicker)
            .accessibilityIdentifier("selectFilesButton")
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose audio files or folders"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = TrackScanner.audioContentTypes + [.folder]

        isPresentingPicker = true
        panel.begin { response in
            isPresentingPicker = false
            if response == .OK {
                onSelect(panel.urls)
            }
        }
    }
}
#endif

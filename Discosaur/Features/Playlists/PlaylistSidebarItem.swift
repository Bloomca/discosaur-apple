import Foundation
import SwiftUI

struct PlaylistSidebarItem: View {
    let playlist: Playlist
    let selectedPlaylistID: Playlist.ID?
    let onRename: (Playlist.ID, String) -> Void
    @State private var newName: String? // nil means the item is not being edited.
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Label {
            if newName != nil {
                nameEditor
            } else {
                Text(playlist.name)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "music.note.list")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                if newName == nil {
                    newName = playlist.name
                } else {
                    isNameFocused = true
                }
            }
            .accessibilityIdentifier("renamePlaylistMenuItem")
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused { commitRename() }
        }
        .onChange(of: selectedPlaylistID) { _, _ in
            // Also finish when another sidebar item is selected without taking
            // keyboard focus (for example, the New playlist button).
            if isNameFocused { commitRename() }
        }
        .onDisappear { commitRename() }
    }

    @ViewBuilder
    private var nameEditor: some View {
        let field = TextField("Playlist name", text: Binding(
            get: { newName ?? playlist.name },
            set: { name in
                if newName != nil { newName = name }
            }
        ))
        .textFieldStyle(.plain)
        .focused($isNameFocused)
        .accessibilityIdentifier("playlistNameEditor")
        .onSubmit { commitRename() }
        .task {
            guard !Task.isCancelled, newName != nil else { return }
            isNameFocused = true
        }

        #if os(macOS)
        field.onExitCommand { cancelRename() }
        #else
        field
        #endif
    }

    private func commitRename() {
        guard let name = newName else { return }
        newName = nil
        isNameFocused = false
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onRename(playlist.id, name)
    }

    private func cancelRename() {
        newName = nil
        isNameFocused = false
    }
}

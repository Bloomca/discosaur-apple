#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @State private var selector = PlaylistSelector()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackList(playlist: selector.playlist)

            Divider()
            PlayerView()
        }
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                if selector.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Opening files/folders")
                }

                SelectFilesButton { urls in
                    Task {
                        await selector.selectFiles(urls)
                        if let playlist = selector.playlist {
                            Player.shared.updatePlaylist(playlist)
                        }
                    }
                }
                .disabled(selector.isLoading)
            }
        }
        .alert("Could not open files", isPresented: Binding(
            get: { selector.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    selector.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(selector.errorMessage ?? "")
        }
    }
}

#Preview {
    MacRootView()
}
#endif

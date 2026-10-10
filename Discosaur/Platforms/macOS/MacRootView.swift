#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @State private var selector = PlaylistSelector()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SelectFilesButton { urls in
                    Task {
                        await selector.selectFiles(urls)
                    }
                }
                .disabled(selector.isLoading)

                if selector.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
            .padding()

            TrackList(tracks: selector.playlist?.tracks ?? [])

            Divider()
            PlayerView()
        }
        .frame(minWidth: 480, minHeight: 320)
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

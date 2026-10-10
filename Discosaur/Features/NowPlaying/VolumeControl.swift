import SwiftUI

struct VolumeControl: View {
    let player: Player

    @State private var isPresentingPopover = false

    private var speakerSymbol: String {
        if player.isMuted { return "speaker.slash.fill" }
        if player.volume == 0 { return "speaker.fill" }
        if player.volume < 1.0 / 3.0 { return "speaker.wave.1.fill" }
        if player.volume < 2.0 / 3.0 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int((player.volume * 100).rounded()))%"
    }

    private var muteTitle: String { player.isMuted ? "Unmute" : "Mute" }

    var body: some View {
        Button {
            isPresentingPopover.toggle()
        } label: {
            Image(systemName: speakerSymbol)
                .frame(width: 24, height: 24)
                .padding(5)
        }
        .buttonStyle(GlassGroupButtonStyle())
        .padding(4)
        .glassEffect(.regular, in: Circle())
        .fixedSize(horizontal: true, vertical: false)
        .help("Volume")
        .accessibilityLabel("Volume")
        .accessibilityValue(player.isMuted ? "Muted" : volumePercentage)
        .accessibilityIdentifier("playerVolume")
        .popover(isPresented: $isPresentingPopover) {
            volumePopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var volumePopover: some View {
        HStack(spacing: 12) {
            Button {
                player.isMuted.toggle()
            } label: {
                Image(systemName: speakerSymbol)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(muteTitle)
            .accessibilityLabel(muteTitle)
            .accessibilityIdentifier("playerMute")

            Slider(
                value: Binding(
                    get: { Double(player.volume) },
                    set: {
                        player.volume = Float($0)
                        // Adjusting the slider makes the chosen volume audible.
                        player.isMuted = false
                    }
                ),
                in: 0...1
            ) {
                Text("Volume")
            }
            .labelsHidden()
            .frame(width: 140)
            .accessibilityValue(volumePercentage)
            .accessibilityIdentifier("playerVolumeSlider")
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume controls")
    }
}

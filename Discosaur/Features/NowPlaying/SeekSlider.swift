import Foundation
import SwiftUI

struct SeekSlider: View {
    let player: Player

    @State private var scrub: Scrub?

    private struct Selection: Hashable {
        let playlistID: UUID?
        let index: Int?
    }

    private struct Scrub {
        let selection: Selection
        var position: TimeInterval
    }

    private var selection: Selection {
        Selection(playlistID: player.activePlaylist?.id, index: player.currentIndex)
    }

    private var duration: TimeInterval {
        guard let duration = player.duration, duration.isFinite, duration > 0 else { return 0 }
        return duration
    }

    private var sliderPosition: TimeInterval {
        let position: TimeInterval
        if let scrub, scrub.selection == selection {
            position = scrub.position
        } else {
            position = player.position
        }
        guard position.isFinite else { return 0 }
        return min(duration, max(0, position))
    }

    var body: some View {
        let renderedSelection = selection
        Slider(
            value: Binding(
                get: { sliderPosition },
                set: { updatePosition($0, for: renderedSelection) }
            ),
            // A disabled slider still needs a nonempty range when duration is unknown.
            in: 0...(duration > 0 ? duration : 1),
            onEditingChanged: { editingChanged($0, for: renderedSelection) }
        ) {
            Text("Playback position")
        }
        // Replacing the control cancels a drag when playback advances to another track.
        .id(renderedSelection)
        .labelsHidden()
        .disabled(!player.canSeek)
        .accessibilityValue("\(PlaybackTime.format(sliderPosition)) of \(player.duration.map(PlaybackTime.format) ?? "unknown")")
        .accessibilityIdentifier("playerSeekSlider")
        .onChange(of: selection) { _, _ in
            scrub = nil
        }
        .onChange(of: player.canSeek) { _, canSeek in
            if !canSeek {
                scrub = nil
            }
        }
    }

    private func updatePosition(_ position: TimeInterval, for renderedSelection: Selection) {
        guard renderedSelection == selection, player.canSeek else { return }
        if var scrub {
            guard scrub.selection == selection else { return }
            scrub.position = position
            self.scrub = scrub
        } else {
            // Keyboard/accessibility changes may arrive without a drag session.
            try? player.seek(to: position)
        }
    }

    private func editingChanged(_ isEditing: Bool, for renderedSelection: Selection) {
        guard renderedSelection == selection else { return }
        if isEditing {
            guard player.canSeek else { return }
            scrub = Scrub(selection: selection, position: player.position)
        } else {
            let completedScrub = scrub
            scrub = nil
            guard let completedScrub, completedScrub.selection == selection, player.canSeek else { return }
            // Keep audio playing during the drag, then seek once when released.
            try? player.seek(to: completedScrub.position)
        }
    }
}

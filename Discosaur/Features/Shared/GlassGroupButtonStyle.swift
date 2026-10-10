import SwiftUI

struct GlassGroupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GroupItem(configuration: configuration)
    }

    private struct GroupItem: View {
        let configuration: ButtonStyle.Configuration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        private var isPressed: Bool { isEnabled && configuration.isPressed }

        private var highlightOpacity: Double {
            guard isEnabled else { return 0 }
            return isPressed ? 0.16 : (isHovering ? 0.08 : 0)
        }

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .background {
                    Circle().fill(Color.primary.opacity(highlightOpacity))
                }
                .scaleEffect(isPressed && !reduceMotion ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

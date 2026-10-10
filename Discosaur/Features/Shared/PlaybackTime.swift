import Foundation

nonisolated enum PlaybackTime {
    static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0, time < Double(Int.max) else { return "---" }

        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = String(format: "%02d", totalSeconds % 60)

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(seconds)"
        }
        return "\(minutes):\(seconds)"
    }
}

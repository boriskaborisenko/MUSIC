import Foundation

enum DurationFormatter {
  static func mmss(_ totalSeconds: Int?) -> String {
    guard let totalSeconds, totalSeconds >= 0 else { return "--:--" }
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  static func mmss(_ totalSeconds: Double) -> String {
    let safe = max(0, Int(totalSeconds.rounded(.down)))
    return mmss(safe)
  }
}


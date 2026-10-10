import Foundation

/// A Codex session or weekly lane stays on display for two minutes after its reset, the same tolerance
/// that treats two reset boundaries as one.
public enum CodexResetDisplayTolerance {
    public static let seconds: TimeInterval = 2 * 60

    public static func finiteResetInstant(_ window: RateWindow) -> Date? {
        guard let resetsAt = window.resetsAt, resetsAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return resetsAt
    }

    public static func resetIsPast(_ window: RateWindow?, now: Date) -> Bool {
        guard let resetsAt = window.flatMap(self.finiteResetInstant) else { return false }
        return now.timeIntervalSince(resetsAt) > self.seconds
    }

    /// The instant after which `resetIsPast` turns true, for scheduling a redraw.
    public static func expiry(of window: RateWindow) -> Date? {
        self.finiteResetInstant(window)?.addingTimeInterval(self.seconds)
    }
}

import Foundation

enum CleanupScheduleInterval: String, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly

    var seconds: TimeInterval {
        switch self {
        case .daily: return 86_400
        case .weekly: return 7 * 86_400
        case .monthly: return 30 * 86_400
        }
    }
}

/// When the next automatic clean is due; the pump around it decides whether now is a good time.
enum CleanupSchedule {
    /// The Mac must have been left alone this long, so a clean never competes with the user.
    static let minimumIdle: TimeInterval = 300

    /// Seconds until due, anchored on the last run or, before any, on when it was switched on.
    static func wait(lastRun: Date?, enabledAt: Date, interval: CleanupScheduleInterval, now: Date) -> TimeInterval {
        (lastRun ?? enabledAt).addingTimeInterval(interval.seconds).timeIntervalSince(now)
    }
}

/// Free space below the threshold is reported once per crossing, never on every check.
enum CleanupSpaceAlert {
    static let defaultThresholdGB = 10
    static let thresholdChoicesGB = [5, 10, 20, 50]

    static func isLow(available: Int64, thresholdGB: Int) -> Bool {
        available < Int64(thresholdGB) * 1_000_000_000
    }

    /// True only on the check that first sees the volume below the line.
    static func shouldAlert(available: Int64, thresholdGB: Int, wasLow: Bool) -> Bool {
        isLow(available: available, thresholdGB: thresholdGB) && !wasLow
    }
}

struct CleanupHistoryEntry: Codable, Equatable, Sendable {
    let date: Date
    let bytes: Int64
    let count: Int
    let isAutomatic: Bool
}

enum CleanupHistory {
    static let limit = 100

    static func appending(_ entry: CleanupHistoryEntry, to entries: [CleanupHistoryEntry]) -> [CleanupHistoryEntry] {
        guard entry.count > 0 else { return entries }
        return Array((entries + [entry]).suffix(limit))
    }

    static func totalBytes(_ entries: [CleanupHistoryEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.bytes }
    }
}

import Foundation
import os

enum CapturePerformance {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CapturePerformance")

    static func completed(_ operation: String, since start: ContinuousClock.Instant) {
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        logger.info("\(operation, privacy: .public) milliseconds=\(milliseconds, privacy: .public)")
    }

    static func closed(_ operation: String = "workspace-closed") {
        logger.info("\(operation, privacy: .public)")
    }
}

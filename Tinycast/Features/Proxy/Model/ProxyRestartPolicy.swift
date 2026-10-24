import Foundation

/// Backoff for a core that keeps exiting: 1, 2, 4… seconds, and five exits in five minutes stop it.
struct ProxyRestartPolicy: Equatable, Sendable {
    static let window: TimeInterval = 300
    static let limit = 5

    private var exits: [Date] = []

    init() {}

    /// The wait before starting again, or nil once the core has failed too often to retry.
    mutating func delay(afterExitAt now: Date) -> Duration? {
        exits = exits.filter { now.timeIntervalSince($0) < Self.window } + [now]
        guard exits.count < Self.limit else { return nil }
        return .seconds(min(1 << (exits.count - 1), 60))
    }

    mutating func reset() {
        exits = []
    }
}

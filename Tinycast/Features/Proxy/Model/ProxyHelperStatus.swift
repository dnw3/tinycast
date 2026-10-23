import Foundation

/// The helper's core as Tinycast sees it: pushed on every change, and asked for on connecting.
struct ProxyHelperStatus: Codable, Equatable, Sendable {
    enum Core: Codable, Equatable, Sendable {
        case stopped
        case starting
        /// `launch` counts the core's starts, so Tinycast knows when its picks need applying again.
        case running(since: Date, launch: Int)
        /// Waiting to start again after the core exited on its own.
        case restarting(attempt: Int)
        /// Stopped after exiting too often, with the end of the core's log.
        case failed(status: Int32, log: String)
    }

    var core = Core.stopped
    /// Counts the helper's changes, so a push that arrives late never undoes a newer one.
    var revision = 0
    var installed: ProxyHelperRecord.Core?
    var placeholderApplied = false
    /// Why the placeholder could not be set or put back; the core runs regardless.
    var dnsProblem: String?

    init() {}
}

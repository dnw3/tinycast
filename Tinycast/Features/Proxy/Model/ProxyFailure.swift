import Foundation

/// Why the proxy is not running as asked, or what a change could not do.
enum ProxyFailure: Equatable, Sendable {
    /// A build made without `Scripts/fetch-mihomo.sh`, with no core downloaded either.
    case coreMissing
    case invalidProfile([ProxyProblem])
    /// The core refused the config, in its own words.
    case rejected(String)
    case storage(String)
    case unreachable
    case coreExited(status: Int32, log: String)
    /// A source the core could not fetch or read, with the core's reason when it gave one.
    case sourceUpdate(UUID, reason: String?)
    /// Rule sets the core could not download, with the first reason it gave.
    case ruleSetUpdate(count: Int, reason: String?)
    /// Checking for, downloading or installing a core release failed; the core in use is unchanged.
    case coreUpdate(ProxyCoreUpdateFailure)
    /// A downloaded core did not start, so it was removed and the previous core started again.
    case coreDidNotStart(tag: String)
    /// The TUN helper did not answer, or is not the one this Tinycast installed.
    case helperUnavailable
    case helper(ProxyHelperFailure)
}

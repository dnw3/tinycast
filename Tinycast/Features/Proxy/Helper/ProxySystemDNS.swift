import Foundation

/// The DNS servers set on the network service macOS routes through, as the placeholder needs them.
protocol ProxySystemDNS {
    /// The service the default route uses; a TUN device is never one, so it holds while connected.
    func primaryServiceID() -> String?
    /// Nil when the service has none of its own and uses the network's.
    func servers(of serviceID: String) throws -> [String]?
    func setServers(_ servers: [String]?, of serviceID: String) throws
}

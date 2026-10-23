import Foundation
import SystemConfiguration

/// The system's network preferences, where `networksetup -setdnsservers` writes as well.
struct ProxySystemDNSService: ProxySystemDNS {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    private static let name = "TinycastProxyHelper"

    func primaryServiceID() -> String? {
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)
        guard let store = SCDynamicStoreCreate(nil, Self.name as CFString, nil, nil),
            let global = SCDynamicStoreCopyValue(store, key) as? [String: Any]
        else { return nil }
        return global[kSCDynamicStorePropNetPrimaryService as String] as? String
    }

    func servers(of serviceID: String) throws -> [String]? {
        guard let preferences = SCPreferencesCreate(nil, Self.name as CFString, nil) else {
            throw Self.lastFailure()
        }
        let dns = try Self.dnsProtocol(of: serviceID, in: preferences)
        let configuration = SCNetworkProtocolGetConfiguration(dns) as? [String: Any]
        return configuration?[kSCPropNetDNSServerAddresses as String] as? [String]
    }

    func setServers(_ servers: [String]?, of serviceID: String) throws {
        guard let preferences = SCPreferencesCreate(nil, Self.name as CFString, nil),
            SCPreferencesLock(preferences, true)
        else { throw Self.lastFailure() }
        defer { SCPreferencesUnlock(preferences) }
        let dns = try Self.dnsProtocol(of: serviceID, in: preferences)
        var configuration = SCNetworkProtocolGetConfiguration(dns) as? [String: Any] ?? [:]
        configuration[kSCPropNetDNSServerAddresses as String] = servers
        guard SCNetworkProtocolSetConfiguration(dns, configuration as CFDictionary),
            SCPreferencesCommitChanges(preferences), SCPreferencesApplyChanges(preferences)
        else { throw Self.lastFailure() }
    }

    /// A service without a DNS entity gets one, as `networksetup` does.
    private static func dnsProtocol(
        of serviceID: String, in preferences: SCPreferences
    ) throws -> SCNetworkProtocol {
        guard let service = SCNetworkServiceCopy(preferences, serviceID as CFString) else {
            throw Failure(description: "network service \(serviceID) no longer exists")
        }
        if let dns = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS) { return dns }
        guard SCNetworkServiceAddProtocolType(service, kSCNetworkProtocolTypeDNS),
            let dns = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS)
        else { throw lastFailure() }
        return dns
    }

    private static func lastFailure() -> Failure {
        Failure(description: String(cString: SCErrorString(SCError())))
    }
}

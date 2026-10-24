import Foundation

/// Sets the placeholder on the primary network service and puts the original back, via the record.
struct ProxyDNSPlaceholder {
    let dns: any ProxySystemDNS

    /// The backup is saved before anything changes, so a crash right after still has it.
    func apply(to record: inout ProxyHelperRecord, saving save: (ProxyHelperRecord) -> Void) throws {
        guard let service = dns.primaryServiceID() else {
            throw Failure(description: "no primary network service")
        }
        if let backup = record.dns, backup.serviceID != service { try restore(&record, saving: save) }
        let current = try dns.servers(of: service)
        if record.dns == nil {
            record.dns = ProxyDNSBackup(serviceID: service, servers: current)
            save(record)
        }
        if current != ProxyDNSBackup.placeholder {
            try dns.setServers(ProxyDNSBackup.placeholder, of: service)
        }
    }

    /// Servers someone changed since are kept; a service that is gone has nothing to restore.
    func restore(_ record: inout ProxyHelperRecord, saving save: (ProxyHelperRecord) -> Void) throws {
        guard let backup = record.dns else { return }
        if let current = try? dns.servers(of: backup.serviceID),
            case .restore(let servers) = backup.restoration(current: current)
        {
            try dns.setServers(servers, of: backup.serviceID)
        }
        record.dns = nil
        save(record)
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }
}

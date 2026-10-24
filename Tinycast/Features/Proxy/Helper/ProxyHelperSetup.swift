import Foundation

/// Root's half of installing, run by the copy the script verified: directory, grant, plist.
enum ProxyHelperSetup {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// Pins this copy's signer, which the script checked is the installing Tinycast's.
    static func install(_ layout: ProxyHelperLayout, uid: UInt32) throws {
        guard let signer = ProxyCodeSignature.current(), signer.identifier == layout.label else {
            throw Failure(description: "the helper is not signed as \(layout.label)")
        }
        let grant = ProxyHelperGrant(appIdentifier: layout.appIdentifier, leafHash: signer.leafHash, uid: uid)
        guard grant.isValid else { throw Failure(description: "the helper's signature cannot be pinned") }
        try ensureDirectory(ProxyHelperLayout.supportDirectory, mode: 0o755)
        try ensureDirectory(layout.root, mode: 0o700)
        try ProxyHelperSupervisor.writeProtected(JSONEncoder().encode(grant), to: layout.grant)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: layout.launchdJob, format: .xml, options: 0)
        try plist.write(to: URL(filePath: layout.launchdPlist), options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0],
            ofItemAtPath: layout.launchdPlist)
    }

    static func restoreDNS(_ layout: ProxyHelperLayout) throws {
        var record = ProxyHelperSupervisor.loadRecord(at: layout.record)
        try ProxyDNSPlaceholder(dns: ProxySystemDNSService()).restore(&record) {
            ProxyHelperSupervisor.save($0, at: layout.record)
        }
    }

    /// Root writes inside, so what is already there must be root's own directory, not a link.
    private static func ensureDirectory(_ path: String, mode: mode_t) throws {
        var info = stat()
        if lstat(path, &info) != 0 {
            guard mkdir(path, mode) == 0 else { throw Failure(description: "cannot create \(path)") }
            guard lstat(path, &info) == 0 else { throw Failure(description: "cannot read \(path)") }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == 0 else {
            throw Failure(description: "\(path) is not a directory owned by root")
        }
        guard chown(path, 0, 0) == 0, chmod(path, mode) == 0 else {
            throw Failure(description: "cannot protect \(path)")
        }
    }
}

import Foundation

/// Row titles derived from folder names; app names come from the effect layer.
enum CleanupNaming {
    /// `appName` maps a bundle ID to the installed app's name, or nil when none is installed.
    static func title(for match: CleanupMatch, leaf: String, appName: (String) -> String?) -> String {
        let target = CleanupCatalog.target(match.target)
        if target.isGeneric, let key = match.key { return appName(key) ?? key }
        switch match.target {
        case .derivedData: return derivedDataProject(leaf)
        case .savedState:
            let bundleID = strippingKnownExtension(leaf)
            return appName(bundleID) ?? bundleID
        default: break
        }
        let pattern = match.pattern
        let labels = Set(target.patterns.compactMap(\.label))
        if pattern.components.contains("*") {
            let literalLeaf = pattern.components.last == "*" ? [] : [leaf]
            let name = (match.captures + literalLeaf).map(strippingKnownExtension).joined(separator: " · ")
            let allWildcard = target.patterns.allSatisfy { $0.components.contains("*") }
            guard labels.count > 1, allWildcard, let label = pattern.label else { return name }
            return label + " · " + name
        }
        guard let label = pattern.label else { return leaf }
        let sharesLabel = target.patterns.count { $0.label == label } > 1
        guard sharesLabel else { return label }
        return labels.count > 1 ? label + " · " + leaf : leaf
    }

    /// Xcode suffixes a project's folder with a 28-letter hash: "Tinycast-dpgxwzfhpqxvdeb…".
    static func derivedDataProject(_ folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        let suffix = folder[folder.index(after: dash)...]
        guard suffix.count == 28, suffix.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return folder }
        return String(folder[..<dash])
    }

    /// Drops the extension a leaf carries for the system, e.g. ".savedState" or ".ipsw".
    static func strippingKnownExtension(_ name: String) -> String {
        for suffix in [".savedState", ".ipsw", ".xcarchive", ".ips", ".crash", ".diag", ".log"]
        where name.count > suffix.count && name.lowercased().hasSuffix(suffix.lowercased()) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}

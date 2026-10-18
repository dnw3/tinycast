import Foundation

/// What the effect layer read about one leftover macOS update item, at one moment.
struct CleanupSystemUpdateEvidence: Equatable, Sendable {
    let modified: Date
    /// When this Mac last booted; an update only applies across a restart.
    let bootTime: Date
    /// Products `/Library/Updates/index.plist` still lists as downloaded and waiting.
    let pendingProducts: Set<String>
    /// System Integrity Protection guards it; not even root may remove it.
    let isRestricted: Bool
}

/// The one audited place outside home Tinycast removes from, with administrator rights.
enum CleanupSystemUpdatePolicy {
    /// macOS stages an update here; the folder itself is `sunlnk` and stays, its contents can go.
    static let installData = "/System/Volumes/Data/macOS Install Data"
    static let updates = "/Library/Updates"
    static let parents = [installData, updates]

    /// SIP-restricted, or the bookkeeping `softwareupdate` reads to decide what is pending.
    static let keptNames: Set<String> = ["locked files", "index.plist", "productmetadata.plist"]

    /// True when `path` is a leftover this policy may offer, judged from its own evidence.
    static func check(path: String, resolvedParent: String?, evidence: CleanupSystemUpdateEvidence?) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        guard parents.contains(parent), resolvedParent == parent, isPlainName(name),
            !keptNames.contains(name.lowercased()), let evidence
        else { return false }
        return isLeftover(name: name, parent: parent, evidence: evidence)
    }

    /// Untouched since before the last boot, and nothing staged waits on it.
    static func isLeftover(name: String, parent: String, evidence: CleanupSystemUpdateEvidence) -> Bool {
        guard !evidence.isRestricted, evidence.modified < evidence.bootTime else { return false }
        if parent == installData { return evidence.pendingProducts.isEmpty }
        return !evidence.pendingProducts.contains(name)
    }

    /// Letters, digits, dot, dash and underscore: nothing a privileged shell could misread.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && name.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "._-".contains(character))
        }
    }

    /// Product keys from `index.plist`'s `ProductPaths`, and the folder names its values point at.
    static func pendingProducts(fromIndex plist: [String: Any]) -> Set<String> {
        guard let paths = plist["ProductPaths"] as? [String: Any] else { return [] }
        var names = Set(paths.keys)
        for case let value as String in paths.values {
            names.insert((value as NSString).lastPathComponent)
            if let first = value.split(separator: "/").first { names.insert(String(first)) }
        }
        return names
    }

    /// One `rm` for every approved path, run once through the system's administrator prompt.
    static func removalScript(paths: [String], prompt: String) -> String? {
        guard !paths.isEmpty else { return nil }
        for path in paths {
            let parent = (path as NSString).deletingLastPathComponent
            guard parents.contains(parent), isPlainName((path as NSString).lastPathComponent) else { return nil }
        }
        let quoted = paths.map { "'" + $0 + "'" }.joined(separator: " ")
        let shell = "/bin/rm -rf -- " + quoted
        return "do shell script \"" + escaped(shell) + "\" with prompt \"" + escaped(prompt)
            + "\" with administrator privileges"
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

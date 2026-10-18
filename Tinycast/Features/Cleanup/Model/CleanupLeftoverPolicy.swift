import Foundation

enum CleanupLeftoverKind: String, Sendable, CaseIterable {
    /// A data folder named for an app nothing on this Mac still provides.
    case appData
    /// A launch agent whose program no longer exists.
    case launchAgent
    /// An editor extension version the editor itself listed as obsolete.
    case editorExtension
    /// A CLI version neither the current link nor the newest install points at.
    case cliVersion

    var target: CleanupTargetID {
        switch self {
        case .appData: return .appLeftovers
        case .launchAgent: return .brokenLaunchAgents
        case .editorExtension: return .obsoleteExtensions
        case .cliVersion: return .oldCLIVersions
        }
    }
}

/// What the effect layer read about one leftover, at one moment.
struct CleanupLeftoverEvidence: Equatable, Sendable {
    let kind: CleanupLeftoverKind
    /// The bundle ID a data folder or agent is named for.
    let identifier: String
    /// LaunchServices knows an app with exactly this ID.
    let isRegistered: Bool
    /// Bundle IDs of installed apps, running apps and loaded launch jobs, lowercased.
    let knownIdentifiers: Set<String>
    /// Newest modification anywhere near the top of the folder.
    let lastModified: Date
    /// For an agent, the program it launches and whether that file exists.
    let program: String?
    let programExists: Bool
    /// For an editor extension, the editor's own obsolete list contains this folder.
    let listedObsolete: Bool
    /// For a CLI version, the versions the current link and the newest install name.
    let keptVersions: Set<String>
    let now: Date
}

/// Leftovers are offered only on positive evidence that nothing still owns them, and always go to
/// the Trash: an app installed somewhere unusual can look removed.
enum CleanupLeftoverPolicy {
    static let minimumIdle: TimeInterval = 30 * 86_400

    /// Data folders named for an app; `Caches`, logs and saved state are other targets' rows.
    static let appDataParents = [
        "Library/Application Support", "Library/Containers", "Library/HTTPStorages", "Library/WebKit"
    ]
    static let launchAgentParent = "Library/LaunchAgents"
    static let editorExtensionParents: [(parent: String, owner: String)] = [
        (".vscode/extensions", "com.microsoft.VSCode"), (".vscode-insiders/extensions", "com.microsoft.VSCodeInsiders"),
        (".cursor/extensions", "com.todesktop.230313mzl4w4u92"), (".windsurf/extensions", "com.exafunction.windsurf")
    ]
    static let cliVersionParents: [(parent: String, link: String, process: String)] = [
        (".local/share/claude/versions", ".local/bin/claude", "claude"),
        (".local/share/cursor-agent/versions", ".local/bin/cursor-agent", "cursor-agent")
    ]

    /// `com.vendor.product` and longer, never Apple's own and never a protected identity folder.
    static func isCandidateIdentifier(_ name: String) -> Bool {
        let lower = name.lowercased()
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }),
            lower.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }),
            !lower.hasPrefix("com.apple."), !lower.hasPrefix("group.")
        else { return false }
        return !CleanupSafetyPolicy.isProtectedName(lower)
    }

    /// Related when either is the other or extends it at a dot: a helper belongs to its app.
    static func isRelated(_ identifier: String, to known: Set<String>) -> Bool {
        let lower = identifier.lowercased()
        return known.contains { other in
            lower == other || lower.hasPrefix(other + ".") || other.hasPrefix(lower + ".")
        }
    }

    static func decide(_ evidence: CleanupLeftoverEvidence) -> Bool {
        switch evidence.kind {
        case .appData:
            return isCandidateIdentifier(evidence.identifier) && !evidence.isRegistered
                && !isRelated(evidence.identifier, to: evidence.knownIdentifiers)
                && evidence.now.timeIntervalSince(evidence.lastModified) >= minimumIdle
        case .launchAgent:
            guard let program = evidence.program, program.hasPrefix("/"), !evidence.programExists else { return false }
            // A missing system path is an OS change, not a leftover of the user's.
            let systemRoots = ["/usr/", "/bin/", "/sbin/", "/System/"]
            return !systemRoots.contains { program.hasPrefix($0) }
                && !evidence.identifier.lowercased().hasPrefix("com.apple.")
        case .editorExtension:
            return evidence.listedObsolete
        case .cliVersion:
            return !evidence.keptVersions.isEmpty && !evidence.keptVersions.contains(evidence.identifier)
        }
    }

    /// The gate's location check, in home-relative components.
    static func isLocation(_ relative: [String], kind: CleanupLeftoverKind) -> Bool {
        let parent = relative.dropLast().joined(separator: "/")
        guard let leaf = relative.last, !leaf.hasPrefix(".") else { return false }
        switch kind {
        case .appData: return appDataParents.contains(parent)
        case .launchAgent: return parent == launchAgentParent && leaf.hasSuffix(".plist")
        case .editorExtension: return editorExtensionParents.contains { $0.parent == parent }
        case .cliVersion: return cliVersionParents.contains { $0.parent == parent }
        }
    }

    /// The identifier a leaf is judged by: a plist's name without `.plist`, else the folder name.
    static func identifier(forLeaf leaf: String, kind: CleanupLeftoverKind) -> String {
        kind == .launchAgent && leaf.hasSuffix(".plist") ? String(leaf.dropLast(".plist".count)) : leaf
    }

    /// Folder names from an editor's `.obsolete` JSON object, which marks each as `true`.
    static func obsoleteExtensions(fromJSON data: Data) -> Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set(object.compactMap { key, value in (value as? Bool) == true ? key : nil })
    }

    /// The versions a CLI keeps: the one its link targets, the newest, and any it can't read.
    static func keptVersions(names: [String], linkTarget: String?) -> Set<String> {
        var kept = Set(names).subtracting(KeepNewestPolicy.removable(names, keep: 1))
        if let linkTarget { kept.insert((linkTarget as NSString).lastPathComponent) }
        return kept
    }
}

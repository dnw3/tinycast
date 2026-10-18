// Adapted from Purge (MIT): https://github.com/jithin-sabu/purge-app/blob/main/LICENSE
import Foundation

enum CleanupRefusal: String, Sendable, CaseIterable {
    case notStandardized
    case outsideHome
    case neverDelete
    case protectedName
    case ownApp
    case symlinkedAncestor
    case notInCatalog
    case evidenceMismatch
}

/// What a discoverer read to propose a leaf; the gate decides again from it, never the discoverer.
enum CleanupEvidence: Equatable, Sendable {
    case project(CleanupProjectEvidence)
    case systemUpdate(CleanupSystemUpdateEvidence)
    case file(CleanupFileEvidence)
    case leftover(CleanupLeftoverEvidence)
    case cloud(CleanupCloudEvidence)
}

enum CleanupVerdict: Equatable, Sendable {
    case allowed(CleanupMatch)
    case refused(CleanupRefusal)
}

/// The filesystem facts the policy needs, read by the caller so the policy stays pure.
struct CleanupPathContext: Sendable {
    let home: String
    /// `realpath` of the home directory.
    let resolvedHome: String
    /// `realpath` of the item's parent; nil when it could not be resolved.
    let resolvedParent: String?
    var evidence: CleanupEvidence?
}

/// Processes whose activity makes a leaf unsafe to remove right now.
struct CleanupRuntime: Equatable, Sendable {
    var runningBundleIDs: Set<String> = []
    /// Executable file names, lowercased.
    var runningProcesses: Set<String> = []
    /// Kernel-reported working directories of the user's processes, symlinks resolved.
    var workingDirectories: Set<String> = []

    static let idle = CleanupRuntime()
}

/// The one gate every removal passes through, at scan time and again just before acting.
enum CleanupSafetyPolicy {
    static func evaluate(
        path: String, expected: CleanupTargetID? = nil, context: CleanupPathContext
    ) -> CleanupVerdict {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard path.hasPrefix("/"), !path.hasSuffix("/"),
            !components.dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { return .refused(.notStandardized) }

        let source = expected.map { CleanupCatalog.target($0).source } ?? .catalog
        if source == .systemUpdate {
            return evaluateSystemUpdate(path: path, expected: expected, context: context)
        }
        if expected == .macOSInstallers {
            return evaluateFile(path: path, relative: nil, expected: expected, context: context)
        }

        let homeComponents = context.home.split(separator: "/").map(String.init)
        let all = Array(components.dropFirst())
        guard all.count > homeComponents.count,
            zip(all, homeComponents).allSatisfy({ isSame($0, $1) })
        else { return .refused(.outsideHome) }
        let relative = Array(all.dropFirst(homeComponents.count))

        let mayEnterUserFolder =
            (source == .project && isProjectHome(relative)) || (source == .personalFile && isFileHome(relative))
            || (source == .cloudDownload && CleanupCloudPolicy.isLocation(relative))
        if isNeverDelete(relative), !mayEnterUserFolder {
            return .refused(.neverDelete)
        }
        if relative.contains(where: { $0.lowercased().hasPrefix(ownBundleIDPrefix) }) {
            return .refused(.ownApp)
        }
        if let owner = namedFolder(relative)?.lowercased(),
            isProtectedName(owner)
                || (isSame(relative[1], "Containers") && protectedContainers.contains(owner))
        {
            return .refused(.protectedName)
        }

        // A symlinked ancestor could aim an allowed leaf at Documents; refuse rather than follow.
        let expectedParent = ([context.resolvedHome] + relative.dropLast()).joined(separator: "/")
        guard let parent = context.resolvedParent, isSame(parent, expectedParent) else {
            return .refused(.symlinkedAncestor)
        }

        switch source {
        case .catalog:
            guard let match = CleanupCatalog.resolve(relative),
                expected == nil || match.target == expected
            else { return .refused(.notInCatalog) }
            return .allowed(match)
        case .project:
            return evaluateProject(path: path, relative: relative, expected: expected, evidence: context.evidence)
        case .personalFile:
            return evaluateFile(path: path, relative: relative, expected: expected, context: context)
        case .cloudDownload:
            guard case .cloud(let evidence) = context.evidence, expected == .iCloudDownloads,
                CleanupCloudPolicy.isLocation(relative), CleanupCloudPolicy.qualifies(evidence)
            else { return .refused(.evidenceMismatch) }
            return .allowed(
                CleanupMatch(
                    target: .iCloudDownloads, pattern: CleanupPattern(relative.joined(separator: "/")), captures: [],
                    isContentsChild: false))
        case .leftover:
            guard case .leftover(let evidence) = context.evidence, evidence.kind.target == expected,
                CleanupLeftoverPolicy.isLocation(relative, kind: evidence.kind),
                CleanupLeftoverPolicy.identifier(forLeaf: relative[relative.count - 1], kind: evidence.kind)
                    == evidence.identifier,
                CleanupLeftoverPolicy.decide(evidence)
            else { return .refused(.evidenceMismatch) }
            return .allowed(
                CleanupMatch(
                    target: evidence.kind.target, pattern: CleanupPattern(relative.joined(separator: "/")),
                    captures: [evidence.identifier], isContentsChild: false))
        case .tool, .systemUpdate:
            // A tool's store is cleaned by the tool's own command; no file in it is ever removed here.
            return .refused(.notInCatalog)
        }
    }

    /// The single audited exception to staying inside home, pinned by `cleanup-test`.
    private static func evaluateSystemUpdate(
        path: String, expected: CleanupTargetID?, context: CleanupPathContext
    ) -> CleanupVerdict {
        guard case .systemUpdate(let evidence) = context.evidence else { return .refused(.outsideHome) }
        guard CleanupSystemUpdatePolicy.check(path: path, resolvedParent: context.resolvedParent, evidence: evidence)
        else { return .refused(.evidenceMismatch) }
        let match = CleanupMatch(
            target: .systemUpdates, pattern: CleanupPattern(path), captures: [], isContentsChild: false)
        return .allowed(match)
    }

    /// A personal file is offered only as a reviewed, trashed row, re-decided from its evidence.
    private static func evaluateFile(
        path: String, relative: [String]?, expected: CleanupTargetID?, context: CleanupPathContext
    ) -> CleanupVerdict {
        guard case .file(let evidence) = context.evidence else {
            return relative == nil ? .refused(.outsideHome) : .refused(.evidenceMismatch)
        }
        if relative == nil {
            let parent = (path as NSString).deletingLastPathComponent
            guard context.resolvedParent == parent else { return .refused(.symlinkedAncestor) }
        }
        guard evidence.kind.target == expected,
            CleanupFilePolicy.verify(path: path, relative: relative, evidence: evidence)
        else { return .refused(.evidenceMismatch) }
        let pattern = CleanupPattern(relative?.joined(separator: "/") ?? path)
        var captures: [String] = []
        if let keeper = evidence.keeper { captures.append(keeper) }
        return .allowed(
            CleanupMatch(target: evidence.kind.target, pattern: pattern, captures: captures, isContentsChild: false))
    }

    /// The walk's own roots; `CleanupFilePolicy` decides what inside them is offered.
    private static func isFileHome(_ relative: [String]) -> Bool {
        guard let first = relative.first else { return false }
        return CleanupFilePolicy.roots.contains { isSame($0, first) }
            && !relative.contains { deniedComponents.contains($0.lowercased()) }
    }

    /// A project's folder is offered from its own evidence, re-decided here rather than trusted.
    private static func evaluateProject(
        path: String, relative: [String], expected: CleanupTargetID?, evidence: CleanupEvidence?
    ) -> CleanupVerdict {
        guard case .project(let project) = evidence,
            CleanupProjectRules.rules.contains(project.rule),
            isSame(path, CleanupProjectPolicy.artifactPath(project)),
            !relative[0].hasPrefix("."), !isSame(relative[0], "Library"),
            case .offered(let id) = CleanupProjectPolicy.decide(project), id == expected
        else { return .refused(.evidenceMismatch) }
        let match = CleanupMatch(
            target: id, pattern: CleanupPattern(relative.joined(separator: "/")), captures: [project.root],
            isContentsChild: false)
        return .allowed(match)
    }

    /// Developers keep code in these never-delete roots; only a project's own artifact passes.
    private static func isProjectHome(_ relative: [String]) -> Bool {
        guard let first = relative.first?.lowercased(), projectHomes.contains(first) else { return false }
        return !relative.contains { deniedComponents.contains($0.lowercased()) }
    }

    private static let projectHomes: Set<String> = ["documents", "desktop", "downloads"]

    static func isProjectInUse(_ match: CleanupMatch, runtime: CleanupRuntime) -> Bool {
        guard CleanupCatalog.target(match.target).source == .project, let root = match.captures.first else {
            return false
        }
        return CleanupProjectPolicy.isInUse(root: root, workingDirectories: runtime.workingDirectories)
    }

    /// The running app or tool that locks this leaf, if any.
    static func runningOwner(of match: CleanupMatch, runtime: CleanupRuntime) -> String? {
        let target = CleanupCatalog.target(match.target)
        var bundleIDs = target.ownerBundleIDs
        if target.isGeneric, let key = match.key, looksLikeBundleID(key) { bundleIDs.append(key) }
        for owner in bundleIDs {
            let lower = owner.lowercased()
            if let running = runtime.runningBundleIDs.first(where: { candidate in
                let running = candidate.lowercased()
                return running == lower || lower.hasPrefix(running + ".") || running.hasPrefix(lower + ".")
            }) {
                return running.count <= owner.count ? running : owner
            }
        }
        return target.ownerProcesses.first { runtime.runningProcesses.contains($0.lowercased()) }
    }

    // MARK: - Rules

    private static let ownBundleIDPrefix = "com.tinycast.app"

    /// Places that hold the user's own data; nothing under them is ever offered.
    static let neverDeletePrefixes: [[String]] = [
        "Library/Keychains", "Library/Preferences", "Library/Mail", "Library/Accounts",
        "Library/Messages", "Library/Cookies", "Library/Calendars", "Library/Safari",
        "Library/Mobile Documents", "Library/CloudStorage", "Library/Group Containers",
        "Library/Application Support/JetBrains", "Library/Application Support/MobileSync",
        "Library/Application Support/AddressBook", "Library/Application Support/com.apple.TCC",
        "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies", ".ssh", ".gnupg"
    ].map { $0.split(separator: "/").map(String.init) }

    /// Audited exceptions inside a never-delete root, each pinned by `cleanup-test`.
    static let neverDeleteExceptions: [[String]] = [
        "Library/Messages/Caches/Previews", "Library/Application Support/MobileSync/Backup"
    ].map { $0.split(separator: "/").map(String.init) }

    /// Components that mark user history even inside an otherwise disposable folder.
    static let deniedComponents: Set<String> = ["localhistory", "workspacestorage", "virtualenvs"]

    static func isNeverDelete(_ relative: [String]) -> Bool {
        if relative.contains(where: { deniedComponents.contains($0.lowercased()) }) { return true }
        let denied = neverDeletePrefixes.contains { hasPrefix(relative, $0) }
        return denied && !neverDeleteExceptions.contains { hasPrefix(relative, $0) }
    }

    /// Wiping these makes identity daemons re-authorize, which floods keychain password prompts.
    static let protectedNames: Set<String> = [
        "cloudkit", "familycircle", "com.apple.accountsd", "com.apple.appleaccountd",
        "com.apple.amsaccountsd", "com.apple.akd",
        "com.apple.authenticationservicescore.authenticationservicesagent",
        "com.apple.identityservicesd", "com.apple.icloudhelper", "com.apple.icloudwebd",
        "com.apple.itunescloudd", "com.apple.icloudnotificationagent", "passkit",
        "com.apple.containermanagerd", "diagnosticreportsfornewhardware"
    ]

    /// Containers macOS guards itself; their caches refuse removal even with Full Disk Access.
    static let protectedContainers: Set<String> = ["com.apple.safari"]

    /// Substrings that close the identity and password classes before a new daemon is seen.
    static let protectedFragments = [
        "account", "icloud", "itunescloud", "appleid", "authkit", "authentication", "authorization",
        "identityservice", "keychain", "passkit", "screentime", "1password", "agilebits",
        "bitwarden", "lastpass", "dashlane", "keepass", "authy", "yubico", "inputmethod"
    ]

    /// System UI goes blank, search and fonts break, and EDR agents report tampering.
    static let protectedPrefixes = [
        "com.apple.finder", "com.apple.dock", "com.apple.controlcenter",
        "com.apple.systempreferences", "com.apple.settings", "com.apple.systemsettings",
        "com.apple.fontregistry", "com.apple.spotlight", "com.apple.launchservices",
        "com.apple.iconservices", "com.apple.homed", "com.apple.homekit", "com.apple.home",
        "com.apple.ap.adprivacyd", "com.apple.shortcuts", "com.apple.passwords",
        "com.apple.screentime", "com.crowdstrike.", "com.sentinelone.", "com.sentinel-labs.",
        "com.eset.", "com.jamf.", "com.jamfsoftware.", "com.paloaltonetworks.",
        "com.cisco.anyconnect", "com.cisco.secureclient"
    ]

    static func isProtectedName(_ lower: String) -> Bool {
        protectedNames.contains(lower) || protectedFragments.contains { lower.contains($0) }
            || protectedPrefixes.contains { lower.hasPrefix($0) }
    }

    /// The app-named folder directly under Caches, Containers or Logs.
    private static func namedFolder(_ relative: [String]) -> String? {
        guard relative.count >= 3, isSame(relative[0], "Library"),
            ["Caches", "Containers", "Logs"].contains(where: { isSame(relative[1], $0) })
        else { return nil }
        return relative[2]
    }

    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty }
            && parts[0].allSatisfy { $0.isLetter }
    }

    /// APFS is case-insensitive, so deny rules must be too or `LIBRARY/Keychains` slips past.
    private static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }

    private static func hasPrefix(_ path: [String], _ prefix: [String]) -> Bool {
        path.count >= prefix.count && zip(path, prefix).allSatisfy { isSame($0, $1) }
    }
}

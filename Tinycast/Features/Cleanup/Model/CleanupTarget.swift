import Foundation

/// The list's sections, in display order.
enum CleanupCategory: String, CaseIterable, Sendable {
    case system
    case browsers
    case developer
    case tools
    case projects
    case files
    case leftovers
    case trash
}

/// Safe means its owner rebuilds it unprompted; only safe targets are preselected or automatic.
enum CleanupTier: String, Sendable {
    case safe
    case review
}

enum CleanupDisposition: String, Sendable {
    case delete
    case trash
    /// The owning tool's own cleanup command removes it; Tinycast deletes nothing itself.
    case command
    /// Owned by root; removed in one `rm` behind the system's administrator prompt.
    case administrator
    /// An iCloud download whose local copy is removed; the file stays in iCloud.
    case evict
}

enum CleanupDeletionMode: String, CaseIterable, Sendable {
    case tiered
    case trashOnly

    func resolve(_ disposition: CleanupDisposition) -> CleanupDisposition {
        self == .trashOnly && disposition == .delete ? .trash : disposition
    }
}

/// A home-relative path where `*` matches exactly one component; scan and delete share it.
struct CleanupPattern: Hashable, Sendable {
    let components: [String]
    /// A brand name for the row, e.g. "npm"; never localized.
    let label: String?
    /// The leaf is emptied rather than removed, so an owner that expects the folder keeps it.
    let contentsOnly: Bool

    init(_ path: String, label: String? = nil, contentsOnly: Bool = false) {
        components = path.split(separator: "/").map(String.init)
        self.label = label
        self.contentsOnly = contentsOnly
    }

    /// The components `*` stood for, or nil when `path` is not exactly this pattern.
    func captures(_ path: [String]) -> [String]? {
        guard path.count == components.count else { return nil }
        var captured: [String] = []
        for (part, expected) in zip(path, components) {
            if expected == "*" {
                captured.append(part)
            } else if part.compare(expected, options: .caseInsensitive) != .orderedSame {
                return nil
            }
        }
        return captured
    }

    /// True when `path` is this pattern's literal prefix, without leaning on a `*`.
    func literallyCovers(_ path: [String]) -> Bool {
        guard path.count <= components.count else { return false }
        return zip(path, components).allSatisfy { part, expected in
            expected != "*" && part.compare(expected, options: .caseInsensitive) == .orderedSame
        }
    }

    /// True when `path` lies at or below something this pattern could match.
    func contains(_ path: [String]) -> Bool {
        path.count >= components.count && covers(Array(path.prefix(components.count)))
    }

    /// True when `path` is this pattern or an ancestor of something it could match.
    func covers(_ path: [String]) -> Bool {
        guard path.count <= components.count else { return false }
        return zip(path, components).allSatisfy { part, expected in
            expected == "*" || part.compare(expected, options: .caseInsensitive) == .orderedSame
        }
    }
}

enum CleanupTargetID: String, CaseIterable, Sendable {
    case appCaches
    case otherAppCaches
    case systemUpdates
    case logs
    case crashReports
    case savedState
    case deviceFirmware
    case messagesPreviews
    case safari
    case chrome
    case edge
    case brave
    case arc
    case vivaldi
    case opera
    case firefox
    case serviceWorkers
    case derivedData
    case xcodeCaches
    case deviceSupport
    case xcodeArchives
    case simulatorCaches
    case packageCaches
    case packageStores
    case editorCaches
    case homebrewCache
    case unavailableSimulators
    case pnpmStore
    case goBuildCache
    case goModuleCache
    case dockerData
    case localSnapshots
    case projectArtifacts
    case projectArtifactsReview
    case installers
    case incompleteDownloads
    case duplicates
    case largeFiles
    case oldFiles
    case macOSInstallers
    case aiModels
    case virtualMachines
    case iosBackups
    case iCloudDownloads
    case appLeftovers
    case brokenLaunchAgents
    case obsoleteExtensions
    case oldCLIVersions
    case trash
}

/// Where a target's leaves come from. Only `.catalog` expands patterns; the rest are proposed by
/// a discoverer and the gate re-checks each one against the evidence that proposed it.
enum CleanupSource: Sendable, Equatable {
    case catalog
    case project
    case tool
    case systemUpdate
    case personalFile
    case leftover
    case cloudDownload
}

struct CleanupTarget: Identifiable, Equatable, Sendable {
    let id: CleanupTargetID
    let category: CleanupCategory
    let tier: CleanupTier
    let disposition: CleanupDisposition
    let patterns: [CleanupPattern]
    var source: CleanupSource = .catalog
    /// Classified one leaf at a time against the cache catalog instead of claiming its patterns.
    var isGeneric = false
    /// Running apps that lock the whole target; generic leaves derive their own owner.
    var ownerBundleIDs: [String] = []
    /// Command-line tools, matched by executable name, that may be writing to the target.
    var ownerProcesses: [String] = []
    /// Leaf names never offered, compared case-insensitively.
    var excludedNames: Set<String> = []
    /// A leaf must be untouched for this long before it is offered.
    var minimumAge: TimeInterval?
    /// Siblings under one parent that are always kept, newest first.
    var keepNewest: Int?
    /// Shown with its size but never checked; the trash is emptied through its own action.
    var isSelectable = true
}

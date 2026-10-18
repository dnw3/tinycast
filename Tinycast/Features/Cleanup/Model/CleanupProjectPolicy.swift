import Foundation

/// What the effect layer read about one artifact folder and its project, at one moment.
struct CleanupProjectEvidence: Equatable, Sendable {
    /// Absolute and standardized; the artifact sits at `root/rule.folder`.
    let root: String
    let rule: CleanupProjectRule
    let hasRootMarker: Bool
    let hasLockfile: Bool
    /// A `refuseWhenPresent` file sits inside the folder.
    let holdsState: Bool
    /// Git tracks a file inside the folder; nil when that could not be checked.
    let isTracked: Bool?
    /// Newest sign of editing anywhere in the project; nil when it could not be read.
    let lastActivity: Date?
    /// The activity walk stopped at its limit, so it proved nothing either way.
    let activityTruncated: Bool
    /// Git holds a lock in the project.
    let isGitLocked: Bool
    let idleDays: Int
    let now: Date
}

enum CleanupProjectVerdict: Equatable, Sendable {
    case offered(CleanupTargetID)
    case hidden(Reason)

    enum Reason: Equatable, Sendable {
        case notThisProject
        case holdsState
        case tracked
        case trackingUnknown
        case recentlyUsed
        case gitBusy
    }
}

/// Which artifacts are offered, and at which tier: safe only when idle, pinned and audited.
enum CleanupProjectPolicy {
    static let defaultIdleDays = 30
    static let idleDayChoices = [7, 14, 30, 60, 90, 180]

    static func decide(_ evidence: CleanupProjectEvidence) -> CleanupProjectVerdict {
        guard evidence.hasRootMarker else { return .hidden(.notThisProject) }
        if evidence.holdsState { return .hidden(.holdsState) }
        switch evidence.isTracked {
        case .some(true): return .hidden(.tracked)
        case nil: return .hidden(.trackingUnknown)
        case .some(false): break
        }
        if evidence.isGitLocked { return .hidden(.gitBusy) }
        let threshold = TimeInterval(evidence.idleDays) * 86_400
        if let last = evidence.lastActivity, !evidence.activityTruncated,
            evidence.now.timeIntervalSince(last) < threshold
        {
            return .hidden(.recentlyUsed)
        }
        let provenIdle = evidence.lastActivity != nil && !evidence.activityTruncated
        let safe = provenIdle && evidence.hasLockfile && !evidence.rule.alwaysReview
        return .offered(safe ? .projectArtifacts : .projectArtifactsReview)
    }

    /// The artifact's own folder, which is what the gate checks the leaf against.
    static func artifactPath(_ evidence: CleanupProjectEvidence) -> String {
        evidence.root + "/" + evidence.rule.folder
    }

    /// Whether a process works inside the project right now, from kernel-reported directories.
    static func isInUse(root: String, workingDirectories: Set<String>) -> Bool {
        let lower = root.lowercased()
        return workingDirectories.contains { directory in
            let candidate = directory.lowercased()
            return candidate == lower || candidate.hasPrefix(lower + "/")
        }
    }
}

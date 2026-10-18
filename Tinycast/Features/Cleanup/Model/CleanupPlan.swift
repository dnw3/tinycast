import Foundation

struct CleanupItem: Identifiable, Hashable, Sendable {
    /// Absolute and standardized; what the selection stores.
    let path: String
    let match: CleanupMatch
    /// Row title, resolved by the scanner.
    let name: String
    /// Nil until the walk lands; bytes on disk, which is what removing it frees.
    var size: Int64?
    /// The walk skipped an unreadable folder, so the size is a floor.
    var isPartial = false
    /// A tool frees at most this much; how much it actually keeps is its own business.
    var isUpperBound = false
    /// Nothing can measure it without root; it counts as zero and reads as unknown.
    var isSizeUnknown = false
    let modified: Date?
    let protection: UninstallProtection

    var id: String { path }
    var target: CleanupTarget { CleanupCatalog.target(match.target) }
}

enum CleanupLock: Equatable, Sendable {
    case running(String)
    case protection(UninstallProtection)
    /// A process is working inside the project the folder belongs to.
    case projectInUse
}

enum CleanupCheckState: Sendable {
    case on
    case off
    case mixed
}

struct CleanupGroup: Identifiable, Equatable, Sendable {
    let target: CleanupTarget
    fileprivate(set) var items: [CleanupItem] = []

    var id: CleanupTargetID { target.id }
    var bytes: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
}

/// One scan's findings, in catalog order; a landed size never reorders a row.
struct CleanupPlan: Equatable, Sendable {
    let generation: Int
    private(set) var groups: [CleanupGroup] = CleanupCatalog.targets.map { CleanupGroup(target: $0) }
    private var index: [String: (group: Int, item: Int)] = [:]

    init(generation: Int) {
        self.generation = generation
    }

    static func == (lhs: CleanupPlan, rhs: CleanupPlan) -> Bool {
        lhs.generation == rhs.generation && lhs.groups == rhs.groups
    }

    var items: [CleanupItem] { groups.flatMap(\.items) }

    func item(_ path: String) -> CleanupItem? {
        index[path].map { groups[$0.group].items[$0.item] }
    }

    func group(_ id: CleanupTargetID) -> CleanupGroup? {
        groups.first { $0.id == id }
    }

    /// Appends in arrival order and ignores a path already listed.
    mutating func add(_ found: [CleanupItem]) {
        for item in found where index[item.path] == nil {
            guard let group = groups.firstIndex(where: { $0.id == item.match.target }) else { continue }
            index[item.path] = (group, groups[group].items.count)
            groups[group].items.append(item)
        }
    }

    /// Drops a size measured for an older scan, so a rescan never shows a stale number.
    mutating func setSize(_ bytes: Int64, isPartial: Bool, forPath path: String, generation: Int) {
        guard generation == self.generation, let position = index[path] else { return }
        groups[position.group].items[position.item].size = bytes
        groups[position.group].items[position.item].isPartial = isPartial
    }

    /// Drops what a run removed; the rest keep their order.
    mutating func remove(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        for group in groups.indices {
            groups[group].items.removeAll { paths.contains($0.path) }
        }
        index = [:]
        for (group, entry) in groups.enumerated() {
            for (item, element) in entry.items.enumerated() { index[element.path] = (group, item) }
        }
    }

    func lock(_ item: CleanupItem, runtime: CleanupRuntime) -> CleanupLock? {
        if !item.protection.isRemovable { return .protection(item.protection) }
        if CleanupSafetyPolicy.isProjectInUse(item.match, runtime: runtime) { return .projectInUse }
        return CleanupSafetyPolicy.runningOwner(of: item.match, runtime: runtime).map(CleanupLock.running)
    }

    func isAvailable(_ item: CleanupItem, runtime: CleanupRuntime, exclusions: [String]) -> Bool {
        item.target.isSelectable && lock(item, runtime: runtime) == nil
            && !CleanupExclusions.contains(item.path, in: exclusions)
    }

    /// What Quick Clean and scheduled runs may take: audited, delete-type and free right now.
    func automaticItems(runtime: CleanupRuntime, exclusions: [String]) -> [CleanupItem] {
        items.filter { item in
            item.target.tier == .safe && item.target.disposition == .delete
                && isAvailable(item, runtime: runtime, exclusions: exclusions)
        }
    }
}

/// The one holder of the checked set; every read intersects it with what is available now.
struct CleanupSelection: Equatable, Sendable {
    private(set) var checked: Set<String> = []

    /// Safe rows arrive checked; a reviewed row is always the user's own pick.
    mutating func preselect(_ items: [CleanupItem]) {
        for item in items where item.target.tier == .safe { checked.insert(item.path) }
    }

    mutating func toggle(_ item: CleanupItem, in plan: CleanupPlan, runtime: CleanupRuntime, exclusions: [String]) {
        if checked.contains(item.path) {
            checked.remove(item.path)
        } else if plan.isAvailable(item, runtime: runtime, exclusions: exclusions) {
            checked.insert(item.path)
        }
    }

    /// Checks every available item unless all already are, which unchecks them instead.
    mutating func toggle(
        _ group: CleanupGroup, in plan: CleanupPlan, runtime: CleanupRuntime, exclusions: [String]
    ) {
        let available = group.items.filter { plan.isAvailable($0, runtime: runtime, exclusions: exclusions) }
        if state(of: group, in: plan, runtime: runtime, exclusions: exclusions) == .on {
            for item in group.items { checked.remove(item.path) }
        } else {
            for item in available { checked.insert(item.path) }
        }
    }

    mutating func set(_ items: [CleanupItem], checked isChecked: Bool) {
        for item in items {
            if isChecked { checked.insert(item.path) } else { checked.remove(item.path) }
        }
    }

    func isChecked(_ item: CleanupItem, in plan: CleanupPlan, runtime: CleanupRuntime, exclusions: [String]) -> Bool {
        checked.contains(item.path) && plan.isAvailable(item, runtime: runtime, exclusions: exclusions)
    }

    func state(
        of group: CleanupGroup, in plan: CleanupPlan, runtime: CleanupRuntime, exclusions: [String]
    ) -> CleanupCheckState {
        let available = group.items.filter { plan.isAvailable($0, runtime: runtime, exclusions: exclusions) }
        let count = available.count { checked.contains($0.path) }
        if count == 0 { return .off }
        return count == available.count ? .on : .mixed
    }

    /// Checked and still available: the only set totals, confirmation and the run may use.
    func effective(in plan: CleanupPlan, runtime: CleanupRuntime, exclusions: [String]) -> [CleanupItem] {
        plan.items.filter { isChecked($0, in: plan, runtime: runtime, exclusions: exclusions) }
    }
}

/// Folders the user told the scan to leave alone; they only ever subtract.
enum CleanupExclusions {
    static func contains(_ path: String, in exclusions: [String]) -> Bool {
        let lower = path.lowercased()
        return exclusions.contains { excluded in
            let prefix = excluded.lowercased()
            return lower == prefix || lower.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
        }
    }
}

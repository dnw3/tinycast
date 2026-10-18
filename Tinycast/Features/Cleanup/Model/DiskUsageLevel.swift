import Foundation

/// One row of the analyzer: a folder or file directly inside the level being viewed.
struct DiskUsageEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        case file
        /// Space the walk can't attribute to anything it read: the system, other users, snapshots.
        case unattributed
        /// A TCC-guarded folder the walk won't open without Full Disk Access.
        case guarded
    }

    let path: String
    let name: String
    let kind: Kind
    /// Bytes on disk; nil until its walk lands.
    var bytes: Int64?
    var isPartial = false

    var id: String { path }
    var canOpen: Bool { kind == .folder }
}

/// The entries of one folder, with their order frozen once every size is known.
struct DiskUsageLevel: Equatable, Sendable {
    enum Listing: Equatable, Sendable {
        case loading
        case listed
        /// The folder itself could not be read, which is not the same as empty.
        case unreadable
    }

    let path: String
    let title: String
    let listing: Listing
    private(set) var entries: [DiskUsageEntry]
    private(set) var total: Int64 = 0
    private var positions: [String: Int] = [:]
    private var pending = 0

    init(path: String, title: String, entries: [DiskUsageEntry], listing: Listing = .listed) {
        self.path = path
        self.title = title
        self.listing = listing
        self.entries = entries
        total = entries.reduce(0) { $0 + ($1.bytes ?? 0) }
        pending = entries.count { $0.bytes == nil && $0.kind != .guarded }
        reindex()
    }

    var isComplete: Bool { listing != .loading && pending == 0 }

    mutating func setSize(_ bytes: Int64, isPartial: Bool, forPath path: String) {
        guard let index = positions[path] else { return }
        if let old = entries[index].bytes {
            total -= old
        } else if entries[index].kind != .guarded {
            pending -= 1
        }
        total += bytes
        entries[index].bytes = bytes
        entries[index].isPartial = isPartial
        if pending == 0 { sortBySize() }
    }

    /// Adds the space the volume reports used but no entry accounts for, once all have landed.
    mutating func attribute(used: Int64, title: String) {
        guard isComplete, !entries.contains(where: { $0.kind == .unattributed }) else { return }
        let remainder = used - total
        guard remainder > 0 else { return }
        entries.append(DiskUsageEntry(path: path + "\u{0}other", name: title, kind: .unattributed, bytes: remainder))
        total += remainder
        sortBySize()
    }

    mutating func remove(_ path: String) {
        guard let index = positions[path] else { return }
        let entry = entries.remove(at: index)
        total -= entry.bytes ?? 0
        if entry.bytes == nil, entry.kind != .guarded { pending -= 1 }
        reindex()
    }

    /// Largest first; ties and guarded rows by name, so the order never flickers.
    private mutating func sortBySize() {
        entries.sort { lhs, rhs in
            let left = lhs.bytes ?? -1
            let right = rhs.bytes ?? -1
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        reindex()
    }

    private mutating func reindex() {
        positions = Dictionary(entries.indices.map { (entries[$0].path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func fraction(of entry: DiskUsageEntry) -> Double {
        guard total > 0, let bytes = entry.bytes else { return 0 }
        return Double(bytes) / Double(total)
    }
}

/// What the analyzer may move to the Trash: inside home, below a top-level folder, outside Library.
enum DiskUsagePolicy {
    static func canTrash(_ path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let relative = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard relative.count >= 2, !relative.contains(where: { $0 == ".." || $0 == "." }) else { return false }
        let first = relative[0].lowercased()
        return first != "library" && !first.hasPrefix(".")
            && !relative.contains { $0.lowercased().hasPrefix("com.tinycast.app") }
    }
}

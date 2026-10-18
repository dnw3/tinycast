import Darwin
import Foundation

/// The analyzer's open levels, one per drill-in; only each level's direct children are held.
@MainActor
@Observable
final class DiskUsageSession {
    private(set) var levels: [DiskUsageLevel] = []
    private(set) var hasFullDiskAccess = true

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var generation = 0

    var isEmpty: Bool { levels.isEmpty }

    func level(at depth: Int) -> DiskUsageLevel? {
        levels.indices.contains(depth) ? levels[depth] : nil
    }

    /// The volume overview: home, apps, the shared Library, and what none of them explain.
    func openRoot() {
        guard levels.isEmpty else { return }
        reset()
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
        let home = NSHomeDirectory()
        let entries = [
            DiskUsageEntry(path: home, name: (home as NSString).lastPathComponent, kind: .folder),
            DiskUsageEntry(path: "/Applications", name: "Applications", kind: .folder),
            DiskUsageEntry(path: "/Library", name: "Library", kind: .folder)
        ]
        let title = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
            .volumeLocalizedName ?? "Macintosh HD"
        levels = [DiskUsageLevel(path: "/", title: title, entries: entries)]
        measure(depth: 0, paths: entries.map(\.path))
    }

    /// Replaces everything deeper than `depth` with `entry`'s folder.
    func enter(_ entry: DiskUsageEntry, from depth: Int) {
        guard entry.canOpen else { return }
        cancelTasks()
        levels = Array(levels.prefix(depth + 1))
        let home = NSHomeDirectory()
        let checksAccess = !hasFullDiskAccess
        let names = (try? FileManager.default.contentsOfDirectory(atPath: entry.path)) ?? []
        var entries: [DiskUsageEntry] = []
        var folders: [String] = []
        for name in names {
            let path = entry.path == "/" ? "/" + name : entry.path + "/" + name
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                if checksAccess, CleanupScanner.isGuarded(path + "/", home: home) {
                    entries.append(DiskUsageEntry(path: path, name: name, kind: .guarded))
                } else {
                    entries.append(DiskUsageEntry(path: path, name: name, kind: .folder))
                    folders.append(path)
                }
            case S_IFREG, S_IFLNK:
                entries.append(
                    DiskUsageEntry(path: path, name: name, kind: .file, bytes: Int64(info.st_blocks) * 512))
            default:
                continue
            }
        }
        levels.append(DiskUsageLevel(path: entry.path, title: entry.name, entries: entries))
        measure(depth: depth + 1, paths: folders)
    }

    func remove(_ path: String) {
        for index in levels.indices { levels[index].remove(path) }
    }

    /// Ends the visit; called whenever the palette leaves the analyzer.
    func leave() {
        reset()
    }

    // MARK: - Private

    private func reset() {
        cancelTasks()
        levels = []
    }

    private func cancelTasks() {
        for task in tasks { task.cancel() }
        tasks = []
        generation += 1
    }

    private func measure(depth: Int, paths: [String]) {
        let generation = generation
        let skipping = hasFullDiskAccess ? [] : CleanupScanner.guardedFolders(home: NSHomeDirectory())
        let task = Task { [weak self] in
            await DiskUsageScanner.measure(paths, skipping: skipping) { [weak self] batch in
                guard let self, generation == self.generation, levels.indices.contains(depth) else { return }
                for (path, size) in batch {
                    levels[depth].setSize(size.bytes, isPartial: size.isPartial, forPath: path)
                }
                if depth == 0, let used = Self.usedBytes() {
                    levels[0].attribute(used: used, title: String(localized: "System & Other"))
                }
            }
        }
        tasks.append(task)
    }

    private nonisolated static func usedBytes() -> Int64? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values?.volumeTotalCapacity, let available = values?.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Int64(total) - available
    }
}

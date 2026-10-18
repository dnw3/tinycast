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
        let entries = [NSHomeDirectory(), "/Applications", "/Library"].map { path in
            DiskUsageEntry(path: path, name: FileManager.default.displayName(atPath: path), kind: .folder)
        }
        let title = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
            .volumeLocalizedName ?? "Macintosh HD"
        levels = [DiskUsageLevel(path: "/", title: title, entries: entries)]
        measure(depth: 0, paths: entries.map(\.path))
    }

    /// Replaces everything deeper than `depth` with `entry`'s folder, listed off the main actor.
    func enter(_ entry: DiskUsageEntry, from depth: Int) {
        guard entry.canOpen else { return }
        cancelTasks()
        levels = Array(levels.prefix(depth + 1))
        levels.append(DiskUsageLevel(path: entry.path, title: entry.name, entries: [], listing: .loading))
        let generation = generation
        let checksAccess = !hasFullDiskAccess
        let task = Task { [weak self] in
            let entries = await Self.list(entry.path, checksAccess: checksAccess)
            guard let self, !Task.isCancelled, generation == self.generation, levels.indices.contains(depth + 1)
            else { return }
            levels[depth + 1] = DiskUsageLevel(
                path: entry.path, title: entry.name, entries: entries ?? [], listing: entries == nil ? .unreadable : .listed)
            measure(depth: depth + 1, paths: (entries ?? []).filter { $0.kind == .folder }.map(\.path))
        }
        tasks.append(task)
    }

    /// Nil when the folder itself can't be read.
    @concurrent
    private nonisolated static func list(_ folder: String, checksAccess: Bool) async -> [DiskUsageEntry]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return nil }
        let home = NSHomeDirectory()
        var entries: [DiskUsageEntry] = []
        for name in names {
            let path = folder == "/" ? "/" + name : folder + "/" + name
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            let title = FileManager.default.displayName(atPath: path)
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let guarded = checksAccess && CleanupScanner.isGuarded(path + "/", home: home)
                entries.append(DiskUsageEntry(path: path, name: title, kind: guarded ? .guarded : .folder))
            case S_IFREG, S_IFLNK:
                entries.append(DiskUsageEntry(path: path, name: title, kind: .file, bytes: Int64(info.st_blocks) * 512))
            default:
                continue
            }
        }
        return entries
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

import Darwin
import Foundation

/// Expands the catalog's patterns into items; sizes are left nil for `DiskUsageScanner`.
nonisolated enum CleanupScanner {
    struct Environment: Sendable {
        let home: String
        let resolvedHome: String
        let hasFullDiskAccess: Bool
        let exclusions: [String]
        let now: Date
        /// The installed app's name for a bundle ID, or nil.
        let appName: @Sendable (String) -> String?
        var projectIdleDays = CleanupProjectPolicy.defaultIdleDays
        var largeFileThreshold = CleanupFilePolicy.defaultLargeThreshold
        /// Installed and running apps' bundle IDs; a leftover is never related to one of these.
        var knownBundleIDs: Set<String> = []
    }

    @concurrent
    static func discover(_ environment: Environment) async -> [CleanupItem] {
        let catalog = discoverCatalog(environment)
        guard !Task.isCancelled else { return [] }
        async let tools = CleanupToolScanner.discover(environment)
        async let files = CleanupFileScanner.discover(environment)
        async let cloud = CleanupCloudScanner.discover(environment)
        let projects = await CleanupProjectScanner.discover(environment)
        let updates = CleanupSystemUpdateScanner.discover(environment)
        let leftovers = CleanupLeftoverScanner.discover(environment)
        // A leftover folder is offered whole, so no catalog row inside it counts its bytes again.
        let roots = leftovers.map { $0.path + "/" }
        let outside = catalog.filter { item in !roots.contains { item.path.hasPrefix($0) } }
        return updates + outside + (await tools) + projects + (await files) + (await cloud) + leftovers
    }

    private static func discoverCatalog(_ environment: Environment) -> [CleanupItem] {
        Signposts.interval("CleanupScanner.discover") {
            var seen = Set<String>()
            var items: [CleanupItem] = []
            let specific = CleanupCatalog.targets.filter { !$0.isGeneric }
            for target in specific {
                guard !Task.isCancelled else { return [] }
                let found = target.patterns.flatMap { leaves(of: $0, target: target, in: environment) }
                for item in keepingNewest(found, of: target) where seen.insert(item.path).inserted {
                    items.append(item)
                }
            }
            items = namingBackups(items)
            let generic = CleanupCatalog.target(.appCaches)
            for pattern in generic.patterns {
                guard !Task.isCancelled else { return [] }
                for item in leaves(of: pattern, target: generic, in: environment)
                where seen.insert(item.path).inserted {
                    items.append(item)
                }
            }
            return items
        }
    }

    /// Fields a scan reads once per leaf, and the runner again before acting.
    struct Inspection: Sendable {
        let facts: PathFacts
        let isDirectory: Bool
        let modified: Date
    }

    static func inspect(_ path: String) -> Inspection? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        var parentInfo = stat()
        let parentIsSticky = stat(parent, &parentInfo) == 0 && (parentInfo.st_mode & S_ISVTX) != 0
        let facts = PathFacts(
            path: path,
            isSymbolicLink: (info.st_mode & S_IFMT) == S_IFLNK,
            isSystemRestricted: info.st_flags & UInt32(SF_RESTRICTED | SF_IMMUTABLE) != 0,
            isUserImmutable: info.st_flags & UInt32(UF_IMMUTABLE) != 0,
            isOwnedByCurrentUser: info.st_uid == geteuid(),
            parentIsWritable: access(parent, W_OK) == 0,
            parentIsSticky: parentIsSticky)
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        return Inspection(facts: facts, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR, modified: modified)
    }

    /// The parent's `realpath`, which is what lets the policy refuse a symlinked ancestor.
    static func context(for path: String, environment: Environment) -> CleanupPathContext {
        let parent = (path as NSString).deletingLastPathComponent
        return CleanupPathContext(
            home: environment.home, resolvedHome: environment.resolvedHome,
            resolvedParent: resolvedPath(parent))
    }

    static func resolvedPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// TCC-guarded without Full Disk Access: listing one raises a system prompt, so it is skipped.
    static func isGuarded(_ path: String, environment: Environment) -> Bool {
        guard !environment.hasFullDiskAccess else { return false }
        return isGuarded(path, home: environment.home)
    }

    /// The TCC prefixes plus the Files and Folders set, each of which prompts on first read.
    static func isGuarded(_ path: String, home: String) -> Bool {
        if UninstallProtectionRules.isTCCProtected(path: path, home: home) { return true }
        if isPhotoLibrary(path) { return true }
        return userFolderPrefixes.contains { folder in
            let prefix = home + "/" + folder
            return path == prefix || path.hasPrefix(prefix + "/")
        }
    }

    /// Photos guards its library wherever it lives; reading inside one asks for Photos access.
    static func isPhotoLibrary(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains(".photoslibrary/") || lower.hasSuffix(".photoslibrary")
    }

    /// The guarded folders as exact paths, for a walk that must step around them.
    static func guardedFolders(home: String) -> Set<String> {
        let relative = UninstallProtectionRules.tccRelativePrefixes.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        return Set((relative + userFolderPrefixes).map { home + "/" + $0 })
    }

    private static let userFolderPrefixes = [".Trash", "Desktop", "Documents", "Downloads", "Library/Mobile Documents"]

    // MARK: - Private

    private static func leaves(
        of pattern: CleanupPattern, target: CleanupTarget, in environment: Environment
    ) -> [CleanupItem] {
        var paths = [environment.home]
        for component in pattern.components {
            if component == "*" {
                paths = paths.flatMap { folder -> [String] in
                    guard !isGuarded(folder + "/", environment: environment),
                        let names = try? FileManager.default.contentsOfDirectory(atPath: folder)
                    else { return [] }
                    return names.filter { !$0.hasPrefix(".") }.sorted().map { folder + "/" + $0 }
                }
            } else {
                paths = paths.map { $0 + "/" + component }
            }
        }
        return paths.compactMap { item(at: $0, pattern: pattern, target: target, in: environment) }
    }

    private static func item(
        at path: String, pattern: CleanupPattern, target: CleanupTarget, in environment: Environment
    ) -> CleanupItem? {
        guard !CleanupExclusions.contains(path, in: environment.exclusions) else { return nil }
        let relative = path.dropFirst(environment.home.count + 1).split(separator: "/").map(String.init)
        let leaf = (path as NSString).lastPathComponent
        if isGuarded(path, environment: environment) {
            // Shown locked without touching it: even a stat inside can be the prompting read.
            guard !pattern.components.contains("*"), let match = CleanupCatalog.resolve(relative) else {
                return nil
            }
            return CleanupItem(
                path: path, match: match,
                name: CleanupNaming.title(for: match, leaf: leaf, appName: environment.appName),
                modified: nil, protection: .needsFullDiskAccess)
        }
        guard let inspection = inspect(path),
            case .allowed(let match) = CleanupSafetyPolicy.evaluate(
                path: path, context: context(for: path, environment: environment)),
            target.isGeneric || match.target == target.id
        else { return nil }
        if let age = target.minimumAge, environment.now.timeIntervalSince(inspection.modified) < age {
            return nil
        }
        let protection = UninstallProtectionRules.classify(
            inspection.facts,
            environment: UninstallEnvironment(
                home: environment.home, hasFullDiskAccess: environment.hasFullDiskAccess))
        guard protection != .missing else { return nil }
        return CleanupItem(
            path: path, match: match,
            name: CleanupNaming.title(for: match, leaf: leaf, appName: environment.appName),
            modified: inspection.modified, protection: protection)
    }

    /// A backup folder is a device UDID; its Info.plist names the device, and the newest is marked.
    private static func namingBackups(_ items: [CleanupItem]) -> [CleanupItem] {
        var dates: [String: Date] = [:]
        var renamed = items.map { item -> CleanupItem in
            guard item.match.target == .iosBackups,
                let info = NSDictionary(contentsOfFile: item.path + "/Info.plist")
            else { return item }
            var copy = item
            let device = info["Device Name"] as? String ?? item.name
            if let date = info["Last Backup Date"] as? Date {
                dates[item.path] = date
                copy = CleanupItem(
                    path: item.path, match: item.match,
                    name: device + " · " + date.formatted(date: .abbreviated, time: .omitted),
                    modified: date, protection: item.protection)
            } else {
                copy = CleanupItem(
                    path: item.path, match: item.match, name: device, modified: item.modified, protection: item.protection)
            }
            return copy
        }
        if let newest = dates.max(by: { $0.value < $1.value })?.key,
            let index = renamed.firstIndex(where: { $0.path == newest })
        {
            let item = renamed[index]
            renamed[index] = CleanupItem(
                path: item.path, match: item.match, name: item.name + " · " + String(localized: "Latest"),
                modified: item.modified, protection: item.protection)
        }
        return renamed
    }

    private static func keepingNewest(_ items: [CleanupItem], of target: CleanupTarget) -> [CleanupItem] {
        guard let keep = target.keepNewest else { return items }
        let byParent = Dictionary(grouping: items) { ($0.path as NSString).deletingLastPathComponent }
        var removable = Set<String>()
        for (parent, siblings) in byParent {
            let names = siblings.map { ($0.path as NSString).lastPathComponent }
            removable.formUnion(KeepNewestPolicy.removable(names, keep: keep).map { parent + "/" + $0 })
        }
        return items.filter { removable.contains($0.path) }
    }
}

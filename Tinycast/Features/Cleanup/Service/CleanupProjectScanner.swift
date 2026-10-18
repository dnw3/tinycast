import Darwin
import Foundation

/// Finds project roots under home and reads the evidence `CleanupProjectPolicy` decides from.
nonisolated enum CleanupProjectScanner {
    /// Deep enough for `~/code/github/<repo>/packages/<pkg>`, shallow enough to finish in seconds.
    static let maxDepth = 6
    /// Directories visited across the whole walk; past it the walk stops rather than run on.
    static let directoryBudget = 60_000
    /// Entries read while gauging one project's activity; past it activity proves nothing.
    static let activityBudget = 20_000

    /// Never walked: system-managed, media libraries, or someone else's tree entirely.
    private static let skippedHomeFolders: Set<String> = [
        "library", "applications", "pictures", "music", "movies", "public"
    ]
    /// Bundles and libraries look like folders but are one document; nothing inside is a project.
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle",
        "logicx", "band", "xcarchive", "xcodeproj", "xcworkspace", "playground", "rtfd", "pages",
        "numbers", "key", "lproj", "kext", "plugin", "appex", "imovielibrary", "dSYM"
    ]
    private static let gitActivityFiles = ["index", "HEAD", "logs/HEAD", "FETCH_HEAD", "ORIG_HEAD"]
    private static let gitLockFiles = ["index.lock", "HEAD.lock"]

    /// Every artifact any rule proposes, with evidence read once per project.
    static func discover(_ environment: CleanupScanner.Environment) async -> [CleanupItem] {
        let roots = projectRoots(environment)
        let git = gitExecutable()
        var items: [CleanupItem] = []
        for root in roots {
            guard !Task.isCancelled else { return [] }
            let found = await evidence(
                forRoot: root, home: environment.home, git: git, idleDays: environment.projectIdleDays, now: environment.now)
            for evidence in found {
                if let item = item(for: evidence, environment: environment) { items.append(item) }
            }
        }
        return items
    }

    /// The runner's fresh read for one item, so it never acts on the scan's evidence.
    static func evidence(
        for item: CleanupItem, environment: CleanupScanner.Environment, now: Date
    ) async -> CleanupEvidence? {
        guard let root = item.match.captures.first else { return nil }
        let path = item.path
        return await evidence(
            forRoot: root, home: environment.home, git: gitExecutable(), idleDays: environment.projectIdleDays,
            now: now)
            .first { CleanupProjectPolicy.artifactPath($0) == path }
            .map(CleanupEvidence.project)
    }

    static func item(for evidence: CleanupProjectEvidence, environment: CleanupScanner.Environment) -> CleanupItem? {
        let path = CleanupProjectPolicy.artifactPath(evidence)
        guard !CleanupExclusions.contains(path, in: environment.exclusions),
            case .offered(let id) = CleanupProjectPolicy.decide(evidence),
            let inspection = CleanupScanner.inspect(path), inspection.isDirectory,
            !inspection.facts.isSymbolicLink
        else { return nil }
        var context = CleanupScanner.context(for: path, environment: environment)
        context.evidence = .project(evidence)
        guard case .allowed(let match) = CleanupSafetyPolicy.evaluate(path: path, expected: id, context: context)
        else { return nil }
        let protection = UninstallProtectionRules.classify(
            inspection.facts,
            environment: UninstallEnvironment(home: environment.home, hasFullDiskAccess: environment.hasFullDiskAccess))
        guard protection != .missing else { return nil }
        let project = (evidence.root as NSString).lastPathComponent
        return CleanupItem(
            path: path, match: match, name: project + " · " + evidence.rule.folder,
            modified: evidence.lastActivity, protection: protection)
    }

    // MARK: - Roots

    /// Directories under home holding at least one rule's marker; nested projects are kept.
    static func projectRoots(_ environment: CleanupScanner.Environment) -> [String] {
        var roots: [String] = []
        var visited = 0
        var stack: [(String, Int)] = [(environment.home, 0)]
        let fm = FileManager.default
        while let (directory, depth) = stack.popLast() {
            guard visited < directoryBudget, !Task.isCancelled else { break }
            visited += 1
            guard !CleanupScanner.isGuarded(directory + "/", environment: environment),
                let names = try? fm.contentsOfDirectory(atPath: directory)
            else { continue }
            let listing = Set(names)
            if depth > 0, !CleanupProjectRules.rules(
                forRootListing: listing, exists: { fm.fileExists(atPath: directory + "/" + $0) }
            ).isEmpty {
                roots.append(directory)
            }
            guard depth < maxDepth else { continue }
            for name in names.sorted().reversed() where shouldDescend(name, depth: depth) {
                let child = directory + "/" + name
                guard isPlainDirectory(child), !CleanupExclusions.contains(child, in: environment.exclusions)
                else { continue }
                stack.append((child, depth + 1))
            }
        }
        return roots
    }

    private static func shouldDescend(_ name: String, depth: Int) -> Bool {
        if name.hasPrefix(".") { return false }
        if depth == 0, skippedHomeFolders.contains(name.lowercased()) { return false }
        if CleanupProjectRules.artifactFolderNames.contains(name) { return false }
        return !packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func isPlainDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    // MARK: - Evidence

    static func evidence(
        forRoot root: String, home: String, git: URL?, idleDays: Int, now: Date
    ) async -> [CleanupProjectEvidence] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        let exists = { (relative: String) in fm.fileExists(atPath: root + "/" + relative) }
        let candidates = CleanupProjectRules.rules(forRootListing: Set(names), exists: exists).filter { rule in
            isPlainDirectory(root + "/" + rule.folder)
        }
        // Two rules can name one folder, e.g. Gradle's and Flutter's `build`; the first wins.
        var seen = Set<String>()
        let rules = candidates.filter { seen.insert($0.folder).inserted }
        guard !rules.isEmpty else { return [] }

        let gitDirectory = gitDirectory(forProject: root, home: home)
        let tracked = await trackedFolders(rules.map(\.folder), root: root, gitDirectory: gitDirectory, git: git)
        let activity = lastActivity(root: root, skipping: Set(rules.map(\.folder)), gitDirectory: gitDirectory)
        let locked = gitDirectory.map { directory in gitLockFiles.contains { pathExists(directory + "/" + $0) } }
        return rules.map { rule in
            let folder = root + "/" + rule.folder
            return CleanupProjectEvidence(
                root: root, rule: rule,
                hasRootMarker: true,
                hasLockfile: rule.lockfiles.contains(where: exists),
                holdsState: rule.refuseWhenPresent.contains { pathExists(folder + "/" + $0) },
                isTracked: tracked.map { $0.contains(rule.folder) },
                lastActivity: activity.date, activityTruncated: activity.truncated,
                isGitLocked: locked ?? false, idleDays: idleDays, now: now)
        }
    }

    private static func pathExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Newest modification of anything a person edits: the project's files and git's own.
    private static func lastActivity(
        root: String, skipping artifacts: Set<String>, gitDirectory: String?
    ) -> (date: Date?, truncated: Bool) {
        var newest: TimeInterval = 0
        var visited = 0
        var stack = [root]
        while let directory = stack.popLast() {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for name in names {
                visited += 1
                if visited > activityBudget { return (newest > 0 ? Date(timeIntervalSince1970: newest) : nil, true) }
                let path = directory + "/" + name
                let relative = String(path.dropFirst(root.count + 1))
                if artifacts.contains(relative) || CleanupProjectRules.neverEditedFolderNames.contains(name) {
                    continue
                }
                var info = stat()
                guard lstat(path, &info) == 0 else { continue }
                let kind = info.st_mode & S_IFMT
                if kind == S_IFDIR {
                    stack.append(path)
                } else if kind == S_IFREG {
                    newest = max(newest, TimeInterval(info.st_mtimespec.tv_sec))
                }
            }
        }
        if let gitDirectory {
            for file in gitActivityFiles {
                var info = stat()
                if lstat(gitDirectory + "/" + file, &info) == 0 {
                    newest = max(newest, TimeInterval(info.st_mtimespec.tv_sec))
                }
            }
        }
        return (newest > 0 ? Date(timeIntervalSince1970: newest) : nil, false)
    }

    // MARK: - Git

    /// The repository's git directory at or above `root`, following a worktree's `gitdir:` file.
    static func gitDirectory(forProject root: String, home: String) -> String? {
        var directory = root
        while directory.hasPrefix(home + "/") {
            let candidate = directory + "/.git"
            var info = stat()
            if lstat(candidate, &info) == 0 {
                if (info.st_mode & S_IFMT) == S_IFDIR { return candidate }
                guard let text = try? String(contentsOfFile: candidate, encoding: .utf8),
                    let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:")
                else { return nil }
                let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                return target.hasPrefix("/") ? target : (directory + "/" + target as NSString).standardizingPath
            }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Which candidate folders hold a tracked file; nil when a repository could not be asked.
    private static func trackedFolders(
        _ folders: [String], root: String, gitDirectory: String?, git: URL?
    ) async -> Set<String>? {
        guard gitDirectory != nil else { return [] }
        guard let git else { return nil }
        let arguments =
            ["-C", root, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "ls-files", "-z", "--"]
            + folders
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        guard let result = try? await ToolRunner.run(git, arguments, timeout: 20, environment: environment),
            result.succeeded
        else { return nil }
        let files = result.output.split(separator: "\0").map(String.init)
        return Set(folders.filter { folder in files.contains { $0 == folder || $0.hasPrefix(folder + "/") } })
    }

    /// A real git, never `/usr/bin/git`: that shim offers to install the developer tools.
    static func gitExecutable() -> URL? {
        let candidates = [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/opt/homebrew/bin/git", "/usr/local/bin/git"
        ]
        return candidates.first { access($0, X_OK) == 0 }.map { URL(fileURLWithPath: $0) }
    }
}

import CryptoKit
import Darwin
import Foundation

/// Walks the folders people fill by hand for installers, unfinished downloads, large, old and
/// duplicate files, and `/Applications` for macOS installers.
nonisolated enum CleanupFileScanner {
    static let maxDepth = 10
    static let entryBudget = 300_000
    /// Bytes read to confirm duplicates; past it remaining sets are left unconfirmed.
    static let hashBudget: Int64 = 8 << 30

    struct Candidate: Sendable {
        let path: String
        let bytes: Int64
        let logicalSize: Int64
        let lastUsed: Date
        let created: Date
        let isRegularFile: Bool
    }

    static func discover(_ environment: CleanupScanner.Environment) async -> [CleanupItem] {
        var candidates: [Candidate] = []
        for root in CleanupFilePolicy.roots {
            let path = environment.home + "/" + root
            guard !CleanupScanner.isGuarded(path + "/", environment: environment) else { continue }
            walk(path, environment: environment, into: &candidates)
            guard !Task.isCancelled else { return [] }
        }
        var items: [CleanupItem] = []
        var claimed = Set<String>()
        for candidate in candidates {
            let name = (candidate.path as NSString).lastPathComponent
            guard let kind = CleanupFilePolicy.classify(
                name: name, bytes: candidate.bytes, lastUsed: candidate.lastUsed,
                isRegularFile: candidate.isRegularFile, largeThreshold: environment.largeFileThreshold,
                now: environment.now),
                kind == .installer || kind == .incompleteDownload
            else { continue }
            if let item = item(candidate, kind: kind, keeper: nil, environment: environment) {
                items.append(item)
                claimed.insert(candidate.path)
            }
        }
        // A keeper is claimed too: its copies are already listed, so it never shows as large.
        for item in await duplicates(candidates.filter { !claimed.contains($0.path) }, environment: environment) {
            items.append(item)
            claimed.insert(item.path)
            if let keeper = item.match.captures.first { claimed.insert(keeper) }
        }
        for candidate in candidates where !claimed.contains(candidate.path) {
            let name = (candidate.path as NSString).lastPathComponent
            guard let kind = CleanupFilePolicy.classify(
                name: name, bytes: candidate.bytes, lastUsed: candidate.lastUsed,
                isRegularFile: candidate.isRegularFile, largeThreshold: environment.largeFileThreshold,
                now: environment.now),
                kind == .large || kind == .old,
                let item = item(candidate, kind: kind, keeper: nil, environment: environment)
            else { continue }
            items.append(item)
        }
        return items + macOSInstallers(environment)
    }

    /// The runner's fresh read for one item.
    static func evidence(for item: CleanupItem, environment: CleanupScanner.Environment) async -> CleanupFileEvidence? {
        guard let kind = CleanupFileKind.allCases.first(where: { $0.target == item.match.target }) else { return nil }
        if kind == .macOSInstaller { return installerEvidence(item.path, now: environment.now) }
        guard let candidate = candidate(item.path) else { return nil }
        var matches = false
        let keeper = item.match.captures.first
        if kind == .duplicate, let keeper, let original = Self.candidate(keeper),
            original.logicalSize == candidate.logicalSize, let kept = digest(keeper, limit: nil)
        {
            matches = kept == digest(item.path, limit: nil)
        }
        return evidence(candidate, kind: kind, keeper: keeper, matchesKeeper: matches, environment: environment)
    }

    // MARK: - Walk

    private static func walk(_ root: String, environment: CleanupScanner.Environment, into candidates: inout [Candidate]) {
        var stack: [(String, Int)] = [(root, 0)]
        var visited = 0
        while let (directory, depth) = stack.popLast() {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where !name.hasPrefix(".") {
                visited += 1
                guard visited <= entryBudget, !Task.isCancelled else { return }
                let path = directory + "/" + name
                guard !CleanupExclusions.contains(path, in: environment.exclusions) else { continue }
                let ext = (name as NSString).pathExtension.lowercased()
                if CleanupFilePolicy.incompleteExtensions.contains(ext), let candidate = candidate(path) {
                    candidates.append(candidate)
                    continue
                }
                if CleanupFilePolicy.isPackage(name) { continue }
                var info = stat()
                guard lstat(path, &info) == 0 else { continue }
                switch info.st_mode & S_IFMT {
                case S_IFDIR where depth < maxDepth: stack.append((path, depth + 1))
                case S_IFREG: if let candidate = candidate(path) { candidates.append(candidate) }
                default: break
                }
            }
        }
    }

    static func candidate(_ path: String) -> Candidate? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let kind = info.st_mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR else { return nil }
        let allocated = Int64(info.st_blocks) * 512
        let bytes = kind == S_IFREG ? (privateSize(path) ?? allocated) : ((try? DiskUsageScanner.measure(path))?.bytes ?? 0)
        let used = max(info.st_atimespec.tv_sec, info.st_mtimespec.tv_sec)
        return Candidate(
            path: path, bytes: bytes, logicalSize: Int64(info.st_size),
            lastUsed: Date(timeIntervalSince1970: TimeInterval(used)),
            created: Date(timeIntervalSince1970: TimeInterval(info.st_birthtimespec.tv_sec)),
            isRegularFile: kind == S_IFREG)
    }

    /// Bytes no clone shares, which is what trashing this one copy actually frees.
    private static func privateSize(_ path: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &request, raw.baseAddress, raw.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            guard raw.load(as: UInt32.self) >= 12 else { return nil }
            return Int64(raw.loadUnaligned(fromByteOffset: 4, as: UInt64.self))
        }
    }

    // MARK: - Duplicates

    /// Same length, then same first megabyte, then same digest; clones are skipped, since trashing
    /// one frees almost nothing.
    private static func duplicates(_ candidates: [Candidate], environment: CleanupScanner.Environment) async -> [CleanupItem] {
        let eligible = candidates.filter {
            $0.isRegularFile && $0.logicalSize >= CleanupFilePolicy.duplicateMinimumBytes
                && $0.bytes >= CleanupFilePolicy.duplicateMinimumBytes / 2
        }
        let bySize = Dictionary(grouping: eligible, by: \.logicalSize).values.filter { $0.count > 1 }
        var budget = hashBudget
        var items: [CleanupItem] = []
        for group in bySize.sorted(by: { $0[0].logicalSize > $1[0].logicalSize }) {
            guard !Task.isCancelled else { return [] }
            let byHead = Dictionary(grouping: group) { digest($0.path, limit: 1 << 20) ?? UUID().uuidString }
            for heads in byHead.values where heads.count > 1 {
                let cost = Int64(heads.count) * heads[0].logicalSize
                guard budget >= cost else { continue }
                budget -= cost
                let byDigest = Dictionary(grouping: heads) { digest($0.path, limit: nil) ?? UUID().uuidString }
                for copies in byDigest.values where copies.count > 1 {
                    guard let keeper = CleanupFilePolicy.keeper(of: copies.map { ($0.path, $0.created) }) else { continue }
                    for copy in copies where copy.path != keeper {
                        let evidence = evidence(
                            copy, kind: .duplicate, keeper: keeper, matchesKeeper: true, environment: environment)
                        if let item = item(copy, evidence: evidence, environment: environment) { items.append(item) }
                    }
                }
            }
        }
        return items
    }

    /// SHA-256 of the whole file, or its first `limit` bytes; nil when it can't be read.
    static func digest(_ path: String, limit: Int?) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            guard let chunk = try? handle.read(upToCount: min(remaining, 1 << 20)), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Installers

    private static func macOSInstallers(_ environment: CleanupScanner.Environment) -> [CleanupItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") else { return [] }
        return names.filter { $0.hasPrefix("Install macOS ") && $0.hasSuffix(".app") }.compactMap { name in
            let path = "/Applications/" + name
            guard !CleanupExclusions.contains(path, in: environment.exclusions),
                let evidence = installerEvidence(path, now: environment.now)
            else { return nil }
            return item(at: path, evidence: evidence, environment: environment)
        }
    }

    private static func installerEvidence(_ path: String, now: Date) -> CleanupFileEvidence? {
        guard let candidate = candidate(path) else { return nil }
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        return CleanupFileEvidence(
            kind: .macOSInstaller, bytes: candidate.bytes, lastUsed: candidate.lastUsed, isRegularFile: false,
            keeper: nil, matchesKeeper: false, bundleID: info?["CFBundleIdentifier"] as? String,
            largeThreshold: CleanupFilePolicy.defaultLargeThreshold, now: now)
    }

    // MARK: - Items

    private static func evidence(
        _ candidate: Candidate, kind: CleanupFileKind, keeper: String?, matchesKeeper: Bool,
        environment: CleanupScanner.Environment
    ) -> CleanupFileEvidence {
        CleanupFileEvidence(
            kind: kind, bytes: candidate.bytes, lastUsed: candidate.lastUsed, isRegularFile: candidate.isRegularFile,
            keeper: keeper, matchesKeeper: matchesKeeper, bundleID: nil,
            largeThreshold: environment.largeFileThreshold, now: environment.now)
    }

    private static func item(
        _ candidate: Candidate, kind: CleanupFileKind, keeper: String?, environment: CleanupScanner.Environment
    ) -> CleanupItem? {
        item(
            candidate,
            evidence: evidence(candidate, kind: kind, keeper: keeper, matchesKeeper: false, environment: environment),
            environment: environment)
    }

    private static func item(
        _ candidate: Candidate, evidence: CleanupFileEvidence, environment: CleanupScanner.Environment
    ) -> CleanupItem? {
        guard var item = item(at: candidate.path, evidence: evidence, environment: environment) else { return nil }
        item.size = candidate.bytes
        return item
    }

    private static func item(
        at path: String, evidence: CleanupFileEvidence, environment: CleanupScanner.Environment
    ) -> CleanupItem? {
        var context = path.hasPrefix(environment.home + "/")
            ? CleanupScanner.context(for: path, environment: environment)
            : CleanupPathContext(
                home: environment.home, resolvedHome: environment.resolvedHome,
                resolvedParent: CleanupScanner.resolvedPath((path as NSString).deletingLastPathComponent))
        context.evidence = .file(evidence)
        guard case .allowed(let match) = CleanupSafetyPolicy.evaluate(
            path: path, expected: evidence.kind.target, context: context),
            let inspection = CleanupScanner.inspect(path)
        else { return nil }
        let protection = UninstallProtectionRules.classify(
            inspection.facts,
            environment: UninstallEnvironment(home: environment.home, hasFullDiskAccess: environment.hasFullDiskAccess))
        guard protection != .missing else { return nil }
        var item = CleanupItem(
            path: path, match: match, name: (path as NSString).lastPathComponent, modified: evidence.lastUsed,
            protection: protection)
        item.size = evidence.bytes
        return item
    }
}

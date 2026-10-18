import CoreServices
import Darwin
import Foundation

/// Reads what still owns each candidate leftover: installed and running apps, launch jobs, and
/// LaunchServices' own registry.
nonisolated enum CleanupLeftoverScanner {
    static func discover(_ environment: CleanupScanner.Environment) -> [CleanupItem] {
        let known = knownIdentifiers(environment)
        var items: [CleanupItem] = []
        for parent in CleanupLeftoverPolicy.appDataParents {
            for name in names(in: environment.home + "/" + parent, environment: environment)
            where CleanupLeftoverPolicy.isCandidateIdentifier(name) {
                let path = environment.home + "/" + parent + "/" + name
                if let item = item(at: path, kind: .appData, known: known, environment: environment) { items.append(item) }
            }
        }
        let agents = environment.home + "/" + CleanupLeftoverPolicy.launchAgentParent
        for name in names(in: agents, environment: environment) where name.hasSuffix(".plist") {
            if let item = item(at: agents + "/" + name, kind: .launchAgent, known: known, environment: environment) {
                items.append(item)
            }
        }
        for editor in CleanupLeftoverPolicy.editorExtensionParents {
            let parent = environment.home + "/" + editor.parent
            for name in names(in: parent, environment: environment) {
                if let item = item(at: parent + "/" + name, kind: .editorExtension, known: known, environment: environment) {
                    items.append(item)
                }
            }
        }
        for cli in CleanupLeftoverPolicy.cliVersionParents {
            let parent = environment.home + "/" + cli.parent
            for name in names(in: parent, environment: environment) {
                if let item = item(at: parent + "/" + name, kind: .cliVersion, known: known, environment: environment) {
                    items.append(item)
                }
            }
        }
        return items
    }

    /// The runner's fresh read for one item.
    static func evidence(for item: CleanupItem, environment: CleanupScanner.Environment) -> CleanupLeftoverEvidence? {
        guard let kind = CleanupLeftoverKind.allCases.first(where: { $0.target == item.match.target }) else { return nil }
        return evidence(for: item.path, kind: kind, known: knownIdentifiers(environment), environment: environment)
    }

    // MARK: - Items

    private static func item(
        at path: String, kind: CleanupLeftoverKind, known: Set<String>, environment: CleanupScanner.Environment
    ) -> CleanupItem? {
        guard !CleanupExclusions.contains(path, in: environment.exclusions),
            let evidence = evidence(for: path, kind: kind, known: known, environment: environment),
            CleanupLeftoverPolicy.decide(evidence)
        else { return nil }
        var context = CleanupScanner.context(for: path, environment: environment)
        context.evidence = .leftover(evidence)
        guard case .allowed(let match) = CleanupSafetyPolicy.evaluate(path: path, expected: kind.target, context: context),
            let inspection = CleanupScanner.inspect(path), !inspection.facts.isSymbolicLink
        else { return nil }
        let protection = UninstallProtectionRules.classify(
            inspection.facts,
            environment: UninstallEnvironment(home: environment.home, hasFullDiskAccess: environment.hasFullDiskAccess))
        guard protection != .missing else { return nil }
        return CleanupItem(
            path: path, match: match, name: title(for: path, kind: kind, evidence: evidence),
            modified: evidence.lastModified, protection: protection)
    }

    private static func title(for path: String, kind: CleanupLeftoverKind, evidence: CleanupLeftoverEvidence) -> String {
        let leaf = (path as NSString).lastPathComponent
        let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        switch kind {
        case .appData: return evidence.identifier + " · " + parent
        case .launchAgent: return evidence.identifier
        case .editorExtension, .cliVersion:
            let tool = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            return (tool as NSString).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                + " · " + leaf
        }
    }

    private static func evidence(
        for path: String, kind: CleanupLeftoverKind, known: Set<String>, environment: CleanupScanner.Environment
    ) -> CleanupLeftoverEvidence? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let leaf = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        let identifier = CleanupLeftoverPolicy.identifier(forLeaf: leaf, kind: kind)
        var program: String?
        var programExists = false
        var listedObsolete = false
        var kept = Set<String>()
        switch kind {
        case .appData:
            break
        case .launchAgent:
            program = launchProgram(atPath: path)
            programExists = program.map { FileManager.default.fileExists(atPath: $0) } ?? false
        case .editorExtension:
            let obsolete = FileManager.default.contents(atPath: parent + "/.obsolete")
                .map(CleanupLeftoverPolicy.obsoleteExtensions) ?? []
            listedObsolete = obsolete.contains(leaf)
        case .cliVersion:
            let names = (try? FileManager.default.contentsOfDirectory(atPath: parent))?.filter { !$0.hasPrefix(".") } ?? []
            let link = CleanupLeftoverPolicy.cliVersionParents.first { environment.home + "/" + $0.parent == parent }
                .flatMap { try? FileManager.default.destinationOfSymbolicLink(atPath: environment.home + "/" + $0.link) }
            kept = CleanupLeftoverPolicy.keptVersions(names: names, linkTarget: link)
        }
        return CleanupLeftoverEvidence(
            kind: kind, identifier: identifier,
            isRegistered: kind == .appData && isRegistered(identifier), knownIdentifiers: known,
            lastModified: newestModification(path), program: program, programExists: programExists,
            listedObsolete: listedObsolete, keptVersions: kept, now: environment.now)
    }

    // MARK: - Facts

    private static func names(in directory: String, environment: CleanupScanner.Environment) -> [String] {
        guard !CleanupScanner.isGuarded(directory + "/", environment: environment),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else { return [] }
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    /// Installed apps, plus every launch job's label and program, so a helper keeps its data.
    static func knownIdentifiers(_ environment: CleanupScanner.Environment) -> Set<String> {
        var known = Set(environment.knownBundleIDs.map { $0.lowercased() })
        let roots = [
            environment.home + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"
        ]
        for root in roots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".plist") {
                let label = String(name.dropLast(".plist".count)).lowercased()
                // A dead agent's own label must not vouch for the folder it left behind.
                if let program = launchProgram(atPath: root + "/" + name),
                    !FileManager.default.fileExists(atPath: program)
                {
                    continue
                }
                known.insert(label)
            }
        }
        return known
    }

    private static func isRegistered(_ identifier: String) -> Bool {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(identifier as CFString, nil)?.takeRetainedValue()
            as? [URL]
        else { return false }
        return !urls.isEmpty
    }

    private static func launchProgram(atPath path: String) -> String? {
        guard let plist = NSDictionary(contentsOfFile: path) else { return nil }
        if let program = plist["Program"] as? String { return program }
        return (plist["ProgramArguments"] as? [String])?.first
    }

    /// The folder and two levels below: enough to see an app still writing, without a full walk.
    private static func newestModification(_ path: String) -> Date {
        var newest: TimeInterval = 0
        var frontier = [(path, 0)]
        var visited = 0
        while let (current, depth) = frontier.popLast(), visited < 2_000 {
            visited += 1
            var info = stat()
            guard lstat(current, &info) == 0 else { continue }
            newest = max(newest, TimeInterval(info.st_mtimespec.tv_sec))
            guard (info.st_mode & S_IFMT) == S_IFDIR, depth < 2,
                let names = try? FileManager.default.contentsOfDirectory(atPath: current)
            else { continue }
            frontier += names.map { (current + "/" + $0, depth + 1) }
        }
        return Date(timeIntervalSince1970: newest)
    }
}

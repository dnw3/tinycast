import Darwin
import Foundation

/// Lists leftover macOS update files and removes them in one administrator-authorized `rm`.
nonisolated enum CleanupSystemUpdateScanner {
    static func discover(_ environment: CleanupScanner.Environment) -> [CleanupItem] {
        let pending = pendingProducts()
        let boot = bootTime()
        var items: [CleanupItem] = []
        for parent in CleanupSystemUpdatePolicy.parents {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent) else { continue }
            for name in names.sorted() {
                let path = parent + "/" + name
                guard !CleanupExclusions.contains(path, in: environment.exclusions),
                    let evidence = evidence(for: path, pending: pending, bootTime: boot),
                    case .allowed(let match) = CleanupSafetyPolicy.evaluate(
                        path: path, expected: .systemUpdates, context: context(for: path, evidence: evidence))
                else { continue }
                items.append(
                    CleanupItem(
                        path: path, match: match, name: title(for: path), modified: evidence.modified,
                        protection: .removable))
            }
        }
        return items
    }

    /// The runner's fresh read for one path.
    static func evidence(for path: String) -> CleanupSystemUpdateEvidence? {
        evidence(for: path, pending: pendingProducts(), bootTime: bootTime())
    }

    static func context(for path: String, evidence: CleanupSystemUpdateEvidence?) -> CleanupPathContext {
        let parent = (path as NSString).deletingLastPathComponent
        return CleanupPathContext(
            home: NSHomeDirectory(), resolvedHome: NSHomeDirectory(),
            resolvedParent: CleanupScanner.resolvedPath(parent), evidence: evidence.map(CleanupEvidence.systemUpdate))
    }

    /// Runs the one privileged removal; the system shows its own password prompt with `prompt`.
    static func remove(_ paths: [String], prompt: String) async -> CleanupFailure? {
        guard let script = CleanupSystemUpdatePolicy.removalScript(paths: paths, prompt: prompt) else {
            return .refused(.evidenceMismatch)
        }
        do {
            let result = try await ToolRunner.run(
                URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script], timeout: nil)
            if result.succeeded { return nil }
            // -128 is the prompt's Cancel button.
            return result.output.contains("-128") ? .cancelled : .toolFailed(result.tail)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .toolMissing
        }
    }

    // MARK: - Facts

    private static func evidence(for path: String, pending: Set<String>, bootTime: Date) -> CleanupSystemUpdateEvidence? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return CleanupSystemUpdateEvidence(
            modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)), bootTime: bootTime,
            pendingProducts: pending,
            isRestricted: info.st_flags & UInt32(SF_RESTRICTED | SF_NOUNLINK) != 0)
    }

    private static func pendingProducts() -> Set<String> {
        let index = CleanupSystemUpdatePolicy.updates + "/index.plist"
        guard let data = FileManager.default.contents(atPath: index),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        return CleanupSystemUpdatePolicy.pendingProducts(fromIndex: plist)
    }

    private static func bootTime() -> Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }

    private static func title(for path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        return parent == CleanupSystemUpdatePolicy.installData ? "macOS Install Data · " + name : "Updates · " + name
    }
}

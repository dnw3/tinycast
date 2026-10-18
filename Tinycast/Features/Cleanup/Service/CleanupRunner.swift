import Darwin
import Foundation

/// The removals themselves, injected so `cleanup-walk-test` never touches the real Trash.
protocol CleanupFileOperations: Sendable {
    func remove(_ path: String) throws
    func trash(_ path: String) throws
    func children(of path: String) throws -> [String]
    func evict(_ path: String) throws
}

struct CleanupSystemFileOperations: CleanupFileOperations {
    func remove(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }

    func children(of path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func evict(_ path: String) throws {
        try FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: path))
    }
}

/// Performs one confirmed run. The confirmation lives in the coordinator, never here.
nonisolated enum CleanupRunner {
    struct Request: Sendable {
        let items: [CleanupItem]
        let mode: CleanupDeletionMode
        let runtime: CleanupRuntime
        let environment: CleanupScanner.Environment
        /// The message the system's administrator prompt shows when a run includes update files.
        var administratorPrompt = ""
    }

    /// Every item is re-evaluated against fresh facts first; a refusal is reported, never skipped.
    @concurrent
    static func run(
        _ request: Request, operations: any CleanupFileOperations = CleanupSystemFileOperations(),
        onProgress: @escaping @Sendable @MainActor (Int64) -> Void = { _ in }
    ) async -> CleanupReport {
        await Signposts.interval("CleanupRunner.run") {
            var report = CleanupReport()
            let privileged = request.items.filter { $0.target.disposition == .administrator }
            if !privileged.isEmpty { await runPrivileged(privileged, request: request, into: &report) }
            for item in request.items where item.target.disposition != .administrator {
                if Task.isCancelled {
                    report.recordFailure(name: item.name, path: item.path, reason: .cancelled)
                    continue
                }
                if item.target.source == .tool {
                    if let failure = await runTool(item, request: request) {
                        report.recordFailure(name: item.name, path: item.path, reason: failure)
                    } else {
                        report.recordDeleted(bytes: item.size ?? 0)
                        await onProgress(item.size ?? 0)
                    }
                    continue
                }
                let evidence = await freshEvidence(for: item, request: request)
                if let failure = recheck(item, request: request, evidence: evidence) {
                    report.recordFailure(name: item.name, path: item.path, reason: failure)
                    continue
                }
                let disposition = request.mode.resolve(item.target.disposition)
                let bytes = item.size ?? 0
                do {
                    if item.match.pattern.contentsOnly {
                        try empty(item, disposition: disposition, request: request, operations: operations)
                    } else {
                        try perform(disposition, on: item.path, operations: operations)
                    }
                    switch disposition {
                    case .delete, .command, .administrator: report.recordDeleted(bytes: bytes)
                    case .evict: report.recordEvicted(bytes: bytes)
                    case .trash: report.recordTrashed(bytes: bytes)
                    }
                    await onProgress(bytes)
                } catch let failure as CleanupFailure {
                    report.recordFailure(name: item.name, path: item.path, reason: failure)
                } catch {
                    guard let failure = failure(from: error) else { continue }
                    report.recordFailure(name: item.name, path: item.path, reason: failure)
                }
            }
            return report
        }
    }

    /// Nil when it may go ahead: still in the catalog, unlocked, and not owned by a running app.
    static func recheck(_ item: CleanupItem, request: Request, evidence: CleanupEvidence? = nil) -> CleanupFailure? {
        let environment = request.environment
        guard let inspection = CleanupScanner.inspect(item.path) else { return nil }
        var context = CleanupScanner.context(for: item.path, environment: environment)
        context.evidence = evidence
        let verdict = CleanupSafetyPolicy.evaluate(path: item.path, expected: item.match.target, context: context)
        let match: CleanupMatch
        switch verdict {
        case .refused(let refusal): return .refused(refusal)
        case .allowed(let allowed): match = allowed
        }
        let protection = UninstallProtectionRules.classify(
            inspection.facts,
            environment: UninstallEnvironment(
                home: environment.home, hasFullDiskAccess: environment.hasFullDiskAccess))
        guard protection.isRemovable else { return .permissionDenied }
        if let owner = CleanupSafetyPolicy.runningOwner(of: match, runtime: request.runtime) {
            return .running(owner)
        }
        if CleanupSafetyPolicy.isProjectInUse(match, runtime: request.runtime) { return .inUse }
        guard !match.pattern.contentsOnly || !inspection.facts.isSymbolicLink else {
            return .refused(.symlinkedAncestor)
        }
        return nil
    }

    /// Children only, each evaluated on its own; the folder its owner expects stays.
    /// Every privileged item is re-evaluated from fresh facts, then all go in one prompt.
    private static func runPrivileged(_ items: [CleanupItem], request: Request, into report: inout CleanupReport) async {
        var approved: [CleanupItem] = []
        for item in items {
            // Already gone counts as done, like any other removal.
            guard let evidence = CleanupSystemUpdateScanner.evidence(for: item.path) else { continue }
            let verdict = CleanupSafetyPolicy.evaluate(
                path: item.path, expected: item.match.target,
                context: CleanupSystemUpdateScanner.context(for: item.path, evidence: evidence))
            if case .refused(let refusal) = verdict {
                report.recordFailure(name: item.name, path: item.path, reason: .refused(refusal))
            } else {
                approved.append(item)
            }
        }
        guard !approved.isEmpty, !Task.isCancelled else { return }
        if let failure = await CleanupSystemUpdateScanner.remove(
            approved.map(\.path), prompt: request.administratorPrompt)
        {
            for item in approved { report.recordFailure(name: item.name, path: item.path, reason: failure) }
            return
        }
        for item in approved {
            if CleanupScanner.inspect(item.path) == nil {
                report.recordDeleted(bytes: item.size ?? 0)
            } else {
                report.recordFailure(name: item.name, path: item.path, reason: .permissionDenied)
            }
        }
    }

    /// The tool deletes inside its own store; Tinycast only checks the tool is not busy.
    private static func runTool(_ item: CleanupItem, request: Request) async -> CleanupFailure? {
        if let owner = CleanupSafetyPolicy.runningOwner(of: item.match, runtime: request.runtime) {
            return .running(owner)
        }
        return await CleanupToolScanner.run(item)
    }

    /// A discovered item is re-read from disk now; the scan's evidence may be minutes old.
    private static func freshEvidence(for item: CleanupItem, request: Request) async -> CleanupEvidence? {
        switch item.target.source {
        case .catalog, .tool, .systemUpdate: return nil
        case .cloudDownload:
            return CleanupCloudScanner.evidence(for: item.path).map(CleanupEvidence.cloud)
        case .leftover:
            return CleanupLeftoverScanner.evidence(for: item, environment: request.environment).map(CleanupEvidence.leftover)
        case .personalFile:
            return await CleanupFileScanner.evidence(for: item, environment: request.environment).map(CleanupEvidence.file)
        case .project:
            return await CleanupProjectScanner.evidence(for: item, environment: request.environment, now: Date())
        }
    }

    private static func empty(
        _ item: CleanupItem, disposition: CleanupDisposition, request: Request,
        operations: any CleanupFileOperations
    ) throws {
        for name in try operations.children(of: item.path) {
            try Task.checkCancellation()
            let child = item.path + "/" + name
            let verdict = CleanupSafetyPolicy.evaluate(
                path: child, expected: item.match.target,
                context: CleanupScanner.context(for: child, environment: request.environment))
            guard case .allowed = verdict else { throw CleanupFailure.refused(.notInCatalog) }
            do {
                try perform(disposition, on: child, operations: operations)
            } catch {
                if let failure = failure(from: error) { throw failure }
            }
        }
    }

    private static func perform(
        _ disposition: CleanupDisposition, on path: String, operations: any CleanupFileOperations
    ) throws {
        switch disposition {
        case .delete: try operations.remove(path)
        case .trash: try operations.trash(path)
        case .evict: try operations.evict(path)
        case .command, .administrator: throw CleanupFailure.refused(.notInCatalog)
        }
    }

    /// From the POSIX code underneath, never from localized text; nil when it is already gone.
    static func failure(from error: any Error) -> CleanupFailure? {
        if error is CancellationError { return .cancelled }
        if let failure = error as? CleanupFailure { return failure }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain { return CleanupFailure.from(errno: Int32(nsError.code)) }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
            underlying.domain == NSPOSIXErrorDomain
        {
            return CleanupFailure.from(errno: Int32(underlying.code))
        }
        switch CocoaError.Code(rawValue: nsError.code) {
        case .fileNoSuchFile, .fileReadNoSuchFile: return nil
        case .fileWriteNoPermission, .fileReadNoPermission: return .permissionDenied
        case .fileWriteVolumeReadOnly: return .readOnly
        case .fileLocking: return .inUse
        default: return .other(Int32(nsError.code))
        }
    }
}

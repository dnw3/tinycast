import AppKit
import CoreGraphics
import Synchronization

/// Cleanup's action surface; every run passes through `performCleanup`'s confirmation.
@MainActor
final class CleanupCoordinator {
    private let session: CleanupSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let appIndex: AppIndex
    private let settings: CleanupSettingsStore
    private let schedule: CleanupScheduleStore
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore
    private var runTask: Task<CleanupReport, Never>?
    private var quickTask: Task<Void, Never>?
    private var progressOwner = 0

    init(
        session: CleanupSession, palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        appIndex: AppIndex, settings: CleanupSettingsStore, schedule: CleanupScheduleStore, core: AppCore
    ) {
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.appIndex = appIndex
        self.settings = settings
        self.schedule = schedule
        self.core = core
    }

    var deletionMode: CleanupDeletionMode { settings.deletionMode }

    // MARK: - Screens

    func show() {
        paletteCoordinator.togglePalette(mode: .cleanup)
    }

    /// Run as the screen opens; a visit already under way keeps its scan.
    func load() {
        session.begin(environment: environment())
    }

    func rescan() {
        guard !session.isCleaning else { return }
        session.rescan(environment: environment())
    }

    func openGroup(_ id: CleanupTargetID) {
        session.focus(id)
        palette.push(mode: .cleanupGroup)
    }

    func closeGroup() {
        _ = palette.pop(preservingSelection: true)
    }

    // MARK: - Running

    /// The one funnel for ↵ and the Actions row, so neither can skip the confirmation.
    func performCleanup() {
        guard !session.isCleaning, quickTask == nil else { return }
        let items = session.effectiveSelection
        guard !items.isEmpty else { return }
        let generation = session.plan.generation
        let mode = deletionMode
        Task {
            guard await core.confirm(
                title: Self.confirmTitle(for: items),
                message: confirmation(for: items, mode: mode), symbol: "trash",
                confirmTitle: String(localized: "Clean Up"))
            else { return }
            // The wait let the scan change or a run start; take only what is still checked and free.
            guard session.plan.generation == generation, !session.isCleaning else { return }
            let current = session.effectiveSelection
            guard !current.isEmpty else { return }
            await run(current, mode: mode)
        }
    }

    /// Sizes still landing make the total a floor, so the title never promises an exact figure.
    private static func confirmTitle(for items: [CleanupItem]) -> String {
        let total = bytes(of: items)
        let size = format(total)
        guard items.contains(where: { $0.size == nil }) else { return String(localized: "Clean Up \(size)?") }
        return total > 0
            ? String(localized: "Clean Up at Least \(size)?") : String(localized: "Clean Up Selected Items?")
    }

    /// Scans on its own, then offers only what automatic cleaning may take: audited, safe, free now.
    func quickClean() {
        guard !session.isCleaning, quickTask == nil else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        progressOwner += 1
        let owner = progressOwner
        core.showProgress(String(localized: "Looking for things to clean…"), onCancel: { [weak self] in
            self?.quickTask?.cancel()
        })
        let environment = environment()
        quickTask = Task { [weak self] in
            let items = await Self.automaticCandidates(environment: environment)
            guard let self else { return }
            defer { quickTask = nil }
            if progressOwner == owner { core.hideProgress() }
            guard !Task.isCancelled else { return }
            var plan = CleanupPlan(generation: 0)
            plan.add(items)
            let automatic = plan.automaticItems(
                runtime: session.runtime, exclusions: settings.resolvedExclusions
            ).filter { ($0.size ?? 0) > 0 }
            guard !automatic.isEmpty else {
                core.showMessage(String(localized: "Nothing to clean right now"))
                return
            }
            let mode = deletionMode
            guard await core.confirm(
                title: String(localized: "Quick Clean \(Self.format(Self.bytes(of: automatic)))?"),
                message: String(localized: "Only items marked safe are cleaned; nothing that needs review is touched.")
                    + "\n" + confirmation(for: automatic, mode: mode),
                symbol: "wand.and.rays", confirmTitle: String(localized: "Clean Up"))
            else { return }
            // A run started from the screen while the dialog was open wins; this one stands down.
            guard !session.isCleaning else { return }
            let exclusions = settings.resolvedExclusions
            let current = automatic.filter { plan.isAvailable($0, runtime: session.runtime, exclusions: exclusions) }
            guard !current.isEmpty else { return }
            await run(current, mode: mode)
        }
    }

    @concurrent
    private nonisolated static func automaticCandidates(
        environment: CleanupScanner.Environment
    ) async -> [CleanupItem] {
        var items = await CleanupScanner.discover(environment)
        let wanted = items.indices.filter { index in
            let target = items[index].target
            return target.tier == .safe && target.disposition == .delete && items[index].protection.isRemovable
        }
        let sizes = SizeCollector()
        await DiskUsageScanner.measure(wanted.map { items[$0].path }) { batch in sizes.add(batch) }
        let measured = sizes.values
        items = wanted.map { index in
            var item = items[index]
            if let size = measured[item.path] {
                item.size = size.bytes
                item.isPartial = size.isPartial
            }
            return item
        }
        return items
    }

    private func run(_ items: [CleanupItem], mode: CleanupDeletionMode, automatic: Bool = false) async {
        session.setCleaning(true)
        progressOwner += 1
        let owner = progressOwner
        if !automatic {
            core.showProgress(String(localized: "Cleaning…"), onCancel: { [weak self] in self?.runTask?.cancel() })
        }
        let before = await Self.availableCapacity()
        var request = CleanupRunner.Request(
            items: items, mode: mode, runtime: await session.freshRuntime(), environment: environment())
        request.administratorPrompt = String(localized: "Tinycast wants to remove leftover macOS update files.")
        let task = Task { await CleanupRunner.run(request) }
        runTask = task
        var report = await task.value
        runTask = nil
        if let before, let after = await Self.availableCapacity() { report.volumeGain = after - before }
        if progressOwner == owner, !automatic { core.hideProgress() }
        session.apply(report, cleaned: items)
        session.setCleaning(false)
        schedule.record(report, automatic: automatic)
        await schedule.refreshSpace()
        if automatic {
            if report.removedCount > 0 {
                core.showMessage(String(localized: "Cleaned automatically: \(Self.summary(of: report))"))
            }
        } else {
            await present(report)
        }
    }

    // MARK: - Automatic

    /// Called by the schedule's pump; stands down unless the Mac is idle and nothing else runs.
    func runScheduled() {
        guard settings.scheduleEnabled, !session.isCleaning, quickTask == nil, !paletteCoordinator.isVisible,
            !core.isShowingDialog, Self.idleSeconds() >= CleanupSchedule.minimumIdle
        else { return }
        let environment = environment()
        quickTask = Task { [weak self] in
            let items = await Self.automaticCandidates(environment: environment)
            guard let self else { return }
            defer { quickTask = nil }
            guard !Task.isCancelled, settings.scheduleEnabled, !session.isCleaning else { return }
            var plan = CleanupPlan(generation: 0)
            plan.add(items)
            let runtime = await session.freshRuntime()
            let automatic = plan.automaticItems(runtime: runtime, exclusions: settings.resolvedExclusions)
                .filter { ($0.size ?? 0) > 0 }
            guard !automatic.isEmpty else {
                schedule.record(CleanupReport(), automatic: true)
                return
            }
            await run(automatic, mode: deletionMode, automatic: true)
        }
    }

    /// Asked once, in the app: the user sees exactly which kinds of item scheduled runs take.
    func setScheduleEnabled(_ enabled: Bool) {
        guard enabled else {
            settings.scheduleEnabled = false
            return
        }
        Task {
            guard await core.confirm(
                title: String(localized: "Clean Up Automatically?"),
                message: String(
                    localized: """
                        While your Mac is idle, Tinycast deletes only items marked safe, such as caches, logs and \
                        build data. Running apps, excluded folders and anything that needs review are never touched.
                        """),
                symbol: "calendar.badge.clock", confirmTitle: String(localized: "Turn On"))
            else { return }
            settings.scheduleEnabled = true
            schedule.markEnabled()
        }
    }

    func presentLowSpace(_ available: Int64) {
        core.showMessage(
            String(localized: "Only \(Self.format(available)) free. Open Disk Cleanup to make room."), tone: .danger)
    }

    /// Seconds since the last key, click, scroll or pointer move.
    private nonisolated static func idleSeconds() -> TimeInterval {
        let kinds: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func confirmation(for items: [CleanupItem], mode: CleanupDeletionMode) -> String {
        let deleted = items.filter { mode.resolve($0.target.disposition) == .delete }
        let trashed = items.filter { mode.resolve($0.target.disposition) == .trash }
        var lines: [String] = []
        if !deleted.isEmpty {
            lines.append(String(localized: "\(Self.format(Self.bytes(of: deleted))) is deleted for good; its owners rebuild it."))
        }
        if !trashed.isEmpty {
            lines.append(
                String(localized: "\(Self.format(Self.bytes(of: trashed))) moves to the Trash, where you can put it back."))
        }
        let evicted = items.filter { $0.target.disposition == .evict }
        if !evicted.isEmpty {
            let bytes = Self.format(Self.bytes(of: evicted))
            lines.append(String(localized: "\(bytes) of iCloud downloads is removed; the files stay in iCloud."))
        }
        let privileged = items.filter { $0.target.disposition == .administrator }
        if !privileged.isEmpty {
            lines.append(
                String(
                    localized: """
                        \(Self.format(Self.bytes(of: privileged))) of leftover macOS updates is removed after you \
                        enter your administrator password.
                        """))
        }
        let tools = Set(items.compactMap { CleanupTool(target: $0.match.target)?.executable }).sorted()
        if !tools.isEmpty {
            lines.append(String(localized: "Cleaned by their own tools: \(tools.formatted(.list(type: .and)))."))
        }
        return lines.joined(separator: "\n")
    }

    private func present(_ report: CleanupReport) async {
        let failures = report.realFailures
        let summary = report.removedCount > 0 ? Self.summary(of: report) : ""
        guard !failures.isEmpty else {
            if report.wasCancelled {
                core.showMessage(summary.isEmpty ? String(localized: "Cancelled") : String(localized: "Cancelled · \(summary)"))
            } else if !summary.isEmpty {
                core.showMessage(summary)
            }
            return
        }
        let listed = failures.prefix(5).map { "\($0.name) — \($0.reason.reason(appName: appName))" }
        let remaining = failures.count - listed.count
        await core.showNotice(
            title: report.removedCount > 0
                ? String(localized: "Some Items Weren’t Cleaned") : String(localized: "Nothing Was Cleaned"),
            message: (summary.isEmpty ? "" : summary + "\n\n") + listed.joined(separator: "\n")
                + (remaining > 0 ? String(localized: "\nand \(remaining) more.") : ""),
            symbol: "trash", tone: .danger)
    }

    static func summary(of report: CleanupReport) -> String {
        let deleted = format(report.deletedBytes)
        let trashed = format(report.trashedBytes)
        var parts: [String] = []
        switch (report.deletedCount > 0, report.trashedCount > 0) {
        case (true, true): parts.append(String(localized: "Deleted \(deleted) · \(trashed) moved to the Trash"))
        case (false, true): parts.append(String(localized: "Moved \(trashed) to the Trash"))
        case (true, false): parts.append(String(localized: "Deleted \(deleted)"))
        case (false, false): break
        }
        if report.evictedCount > 0 {
            parts.append(String(localized: "Removed \(format(report.evictedBytes)) of iCloud downloads"))
        }
        if report.isHeldBySnapshots {
            parts.append(String(localized: "Some space returns as local snapshots expire"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Maintenance

    enum Maintenance {
        case rebuildThumbnails
        case restartDock

        var command: (executable: String, arguments: [String]) {
            switch self {
            case .rebuildThumbnails: return ("/usr/bin/qlmanage", ["-r", "cache"])
            case .restartDock: return ("/usr/bin/killall", ["Dock"])
            }
        }
    }

    /// Small fixes macOS offers no button for; each is undone by simply using the Mac.
    func runMaintenance(_ task: Maintenance) {
        let command = task.command
        Task {
            let result = try? await ToolRunner.run(URL(fileURLWithPath: command.executable), command.arguments, timeout: 30)
            guard let result, result.succeeded else {
                let tail = result?.tail ?? ""
                core.showMessage(
                    tail.isEmpty ? String(localized: "Couldn’t finish") : String(localized: "Couldn’t finish: \(tail)"),
                    tone: .danger)
                return
            }
            switch task {
            case .rebuildThumbnails: core.showMessage(String(localized: "Thumbnails will be rebuilt as Finder needs them"))
            case .restartDock: core.showMessage(String(localized: "Dock restarted"))
            }
        }
    }

    // MARK: - Row actions

    func copyPath(_ path: String) {
        Paster.copyPlainText(path)
        core.showMessage(String(localized: "Copied path"))
    }

    func showInFinder(_ path: String) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(URL(fileURLWithPath: path))
    }

    /// Quits the app holding a row, which relocks it free as soon as the app is gone.
    func quitOwner(of item: CleanupItem) {
        guard case .running(let owner) = session.lock(item) else { return }
        _ = AppLauncher.quit(bundleID: owner)
    }

    /// Remembers the folder so no later scan offers it, and drops it from this one now.
    func exclude(_ path: String) {
        settings.exclude(path)
        session.forget(Set(session.plan.items.map(\.path).filter {
            CleanupExclusions.contains($0, in: settings.resolvedExclusions)
        }))
        core.showMessage(String(localized: "Won’t scan \((path as NSString).lastPathComponent) again"))
    }

    func openFullDiskAccessSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Permissions.openFullDiskAccessSettings()
    }

    func openSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.settingsCoordinator.showSettings(tab: .cleanup)
    }

    func emptyTrash() {
        core.systemActionCoordinator.runSystemAction(id: .emptyTrash)
    }

    // MARK: - Names

    /// The launcher's own names, so a row reads as the app does everywhere else.
    func appName(_ bundleID: String) -> String {
        appIndex.apps.first { $0.kind == .application && $0.bundleID?.lowercased() == bundleID.lowercased() }?
            .name ?? bundleID
    }

    private func environment() -> CleanupScanner.Environment {
        var names: [String: String] = [:]
        for app in appIndex.apps where app.kind == .application {
            guard let bundleID = app.bundleID?.lowercased(), names[bundleID] == nil else { continue }
            names[bundleID] = app.name
        }
        var environment = CleanupAccess.environment(exclusions: settings.resolvedExclusions, appNames: names)
        environment.projectIdleDays = settings.projectIdleDays
        environment.largeFileThreshold = settings.largeFileThreshold
        environment.knownBundleIDs = Set(names.keys).union(session.runtime.runningBundleIDs.map { $0.lowercased() })
        return environment
    }

    nonisolated static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    private static func bytes(of items: [CleanupItem]) -> Int64 {
        items.reduce(0) { $0 + ($1.size ?? 0) }
    }

    @concurrent
    private nonisolated static func availableCapacity() async -> Int64? {
        CleanupAccess.availableCapacity()
    }
}

/// Gathers streamed sizes for a run that has no screen to stream them into.
private final class SizeCollector: Sendable {
    private let storage = Mutex<[String: DiskUsageScanner.Measurement]>([:])

    var values: [String: DiskUsageScanner.Measurement] { storage.withLock { $0 } }

    func add(_ batch: [(String, DiskUsageScanner.Measurement)]) {
        storage.withLock { values in
            for (path, size) in batch { values[path] = size }
        }
    }
}

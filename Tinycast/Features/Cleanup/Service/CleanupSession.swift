import Foundation

/// One visit to the cleanup screens: the scan, its plan and what is checked.
@MainActor
@Observable
final class CleanupSession {
    enum Phase: Equatable {
        case idle
        case discovering
        case measuring
        case ready
    }

    struct Capacity: Equatable {
        let total: Int64
        let available: Int64
    }

    private(set) var phase: Phase = .idle
    private(set) var plan = CleanupPlan(generation: 0)
    private(set) var selection = CleanupSelection()
    private(set) var hasFullDiskAccess = true
    private(set) var capacity: Capacity?
    private(set) var isCleaning = false
    /// The group the detail screen shows, kept after returning so the parent lands back on it.
    private(set) var focusedGroupID: CleanupTargetID?
    /// The group's items, largest first, frozen when it was opened so landing sizes never reorder.
    private(set) var focusedOrder: [String] = []

    @ObservationIgnored private let runningApps: RunningAppsMonitor
    @ObservationIgnored private let settings: CleanupSettingsStore
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var processes = CleanupAccess.ProcessSnapshot()

    init(runningApps: RunningAppsMonitor, settings: CleanupSettingsStore) {
        self.runningApps = runningApps
        self.settings = settings
    }

    /// Read live from the settings, so a folder excluded mid-visit drops out of every total at once.
    var exclusions: [String] { settings.resolvedExclusions }

    /// Live: an app launching or quitting relocks its rows without a rescan.
    var runtime: CleanupRuntime {
        CleanupRuntime(
            runningBundleIDs: runningApps.runningBundleIDs, runningProcesses: processes.names,
            workingDirectories: processes.workingDirectories)
    }

    /// Re-samples processes so a run judges running tools and busy projects as they are now.
    func freshRuntime() async -> CleanupRuntime {
        processes = await Self.sampleProcesses()
        return runtime
    }

    var isScanning: Bool { phase == .discovering || phase == .measuring }

    var groups: [CleanupGroup] { plan.groups.filter { !$0.items.isEmpty && !$0.isEmptyOnDisk } }

    var effectiveSelection: [CleanupItem] {
        selection.effective(in: plan, runtime: runtime, exclusions: exclusions)
    }

    var hasEffectiveSelection: Bool { selection.hasEffective(in: plan, runtime: runtime, exclusions: exclusions) }

    var selectedBytes: Int64 { effectiveSelection.reduce(0) { $0 + ($1.size ?? 0) } }

    /// What is safe to clean right now, checked or not, by category; the overview's whole figure.
    var reclaimableBytesByCategory: [CleanupCategory: Int64] {
        plan.reclaimableItems(runtime: runtime, exclusions: exclusions).reduce(into: [:]) { totals, item in
            totals[item.target.category, default: 0] += item.size ?? 0
        }
    }

    // MARK: - Scanning

    /// Starts a scan unless this visit already has one.
    func begin(environment: CleanupScanner.Environment) {
        guard phase == .idle else { return }
        rescan(environment: environment)
    }

    func rescan(environment: CleanupScanner.Environment) {
        scanTask?.cancel()
        generation += 1
        let generation = generation
        plan = CleanupPlan(generation: generation)
        selection = CleanupSelection()
        focusedGroupID = nil
        focusedOrder = []
        hasFullDiskAccess = environment.hasFullDiskAccess
        phase = .discovering
        // One volume query, read now so the storage bar fills the pane while discovery runs.
        capacity = Self.readCapacitySync()
        scanTask = Task { [weak self] in
            self?.processes = await Self.sampleProcesses()
            let skipping = environment.hasFullDiskAccess ? [] : CleanupScanner.guardedFolders(home: environment.home)
            await CleanupScanner.discover(environment) { [weak self] items in
                await self?.receive(items, generation: generation, skipping: skipping)
            }
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            phase = .ready
        }
    }

    /// Lists one source's findings at once and measures them before taking the next.
    private func receive(_ items: [CleanupItem], generation: Int, skipping: Set<String>) async {
        guard !Task.isCancelled, generation == self.generation else { return }
        plan.add(items)
        selection.preselect(items)
        phase = .measuring
        let paths = items.filter { $0.size == nil && $0.protection.isRemovable }.map(\.path)
        await DiskUsageScanner.measure(paths, skipping: skipping) { [weak self] batch in
            guard let self, generation == self.generation else { return }
            for (path, size) in batch {
                plan.setSize(size.bytes, isPartial: size.isPartial, forPath: path, generation: generation)
            }
        }
    }

    /// Ends the visit; called whenever the palette leaves both cleanup screens.
    func leave() {
        scanTask?.cancel()
        scanTask = nil
        generation += 1
        phase = .idle
        plan = CleanupPlan(generation: generation)
        selection = CleanupSelection()
        focusedGroupID = nil
        focusedOrder = []
    }

    // MARK: - Selection

    func toggle(_ item: CleanupItem) {
        selection.toggle(item, in: plan, runtime: runtime, exclusions: exclusions)
    }

    func toggle(_ group: CleanupGroup) {
        selection.toggle(group, in: plan, runtime: runtime, exclusions: exclusions)
    }

    func isChecked(_ item: CleanupItem) -> Bool {
        selection.isChecked(item, in: plan, runtime: runtime, exclusions: exclusions)
    }

    func state(of group: CleanupGroup) -> CleanupCheckState {
        selection.state(of: group, in: plan, runtime: runtime, exclusions: exclusions)
    }

    func lock(_ item: CleanupItem) -> CleanupLock? {
        plan.lock(item, runtime: runtime)
    }

    func isAvailable(_ group: CleanupGroup) -> Bool {
        group.items.contains { plan.isAvailable($0, runtime: runtime, exclusions: exclusions) }
    }

    func selectSafe() {
        selection.set(plan.items.filter { $0.target.tier == .safe }, checked: true)
    }

    func deselectAll() {
        selection.set(plan.items, checked: false)
    }

    /// Drops an excluded row from this visit; the next scan never finds it.
    func forget(_ paths: Set<String>) {
        selection.set(plan.items.filter { paths.contains($0.path) }, checked: false)
        plan.remove(paths)
        focusedOrder.removeAll { plan.item($0) == nil }
    }

    // MARK: - Detail

    func focus(_ group: CleanupTargetID) {
        focusedGroupID = group
        let items = plan.group(group)?.items ?? []
        focusedOrder = items.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.map(\.path)
    }

    var focusedItems: [CleanupItem] { focusedOrder.compactMap { plan.item($0) }.filter { !$0.isEmptyOnDisk } }

    // MARK: - Running

    func setCleaning(_ cleaning: Bool) {
        isCleaning = cleaning
    }

    /// Drops what a run removed, so the rows and totals reflect the disk without a rescan.
    func apply(_ report: CleanupReport, cleaned: [CleanupItem]) {
        let failed = Set(report.failures.map(\.path))
        plan.remove(Set(cleaned.map(\.path)).subtracting(failed))
        focusedOrder.removeAll { plan.item($0) == nil }
        capacity = Self.readCapacitySync()
    }

    @concurrent
    private nonisolated static func sampleProcesses() async -> CleanupAccess.ProcessSnapshot {
        CleanupAccess.processSnapshot()
    }

    /// Finder's figure: available includes purgeable space, so the two numbers agree.
    private nonisolated static func readCapacitySync() -> Capacity? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values?.volumeTotalCapacity,
            let available = values?.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Capacity(total: Int64(total), available: available)
    }
}

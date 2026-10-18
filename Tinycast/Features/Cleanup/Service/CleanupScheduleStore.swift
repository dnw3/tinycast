import Foundation

/// The automatic side of Disk Cleanup: the schedule's clock, the free-space watch, and the history
/// of every run. It decides when; the coordinator does the cleaning.
@MainActor
@Observable
final class CleanupScheduleStore {
    /// Keeps the first evaluation clear of the login rush.
    private static let startupDelay = Duration.seconds(60)
    /// Free space is read this often; a due clean that was withheld is retried as often.
    private static let checkInterval: TimeInterval = 900

    @ObservationIgnored var onScheduledRunDue: (@MainActor () -> Void)?
    @ObservationIgnored var onLowSpace: (@MainActor (Int64) -> Void)?

    /// Free bytes while below the alert threshold, for the menu-bar row; nil when there is room.
    private(set) var lowSpaceAvailable: Int64?
    private(set) var history: [CleanupHistoryEntry]

    @ObservationIgnored private let settings: CleanupSettingsStore
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var state: State
    @ObservationIgnored private var pump: Task<Void, Never>?

    init(settings: CleanupSettingsStore) {
        self.settings = settings
        fileURL = AppPaths.applicationSupport().appendingPathComponent("cleanup-schedule.json")
        let stored = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        state = stored ?? State()
        history = state.history
    }

    deinit { pump?.cancel() }

    var lastRun: CleanupHistoryEntry? { history.last }
    var totalFreed: Int64 { CleanupHistory.totalBytes(history) }

    func start() {
        pump?.cancel()
        pump = Task { [weak self] in
            try? await Task.sleep(for: Self.startupDelay)
            while !Task.isCancelled {
                guard let wait = await self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// The clock starts when the user switches scheduling on, so the first run is a full interval away.
    func markEnabled(at now: Date = Date()) {
        state.enabledAt = now
        persist()
    }

    func record(_ report: CleanupReport, automatic: Bool, at now: Date = Date()) {
        let entry = CleanupHistoryEntry(date: now, bytes: report.removedBytes, count: report.removedCount, isAutomatic: automatic)
        state.history = CleanupHistory.appending(entry, to: state.history)
        if automatic { state.lastAutomaticRunAt = now }
        history = state.history
        persist()
    }

    func clearHistory() {
        state.history = []
        history = []
        persist()
    }

    /// Re-reads free space now, e.g. after a run, so the menu-bar row never lingers.
    func refreshSpace() async {
        await checkSpace(alerting: false)
    }

    // MARK: - Private

    private func advance() async -> TimeInterval {
        await checkSpace(alerting: true)
        guard settings.scheduleEnabled else { return Self.checkInterval }
        let wait = CleanupSchedule.wait(
            lastRun: state.lastAutomaticRunAt, enabledAt: state.enabledAt ?? Date(), interval: settings.scheduleInterval,
            now: Date())
        guard wait <= 0 else { return min(wait, Self.checkInterval) }
        onScheduledRunDue?()
        return Self.checkInterval
    }

    private func checkSpace(alerting: Bool) async {
        guard settings.lowSpaceAlertEnabled, let available = await Self.availableBytes() else {
            lowSpaceAvailable = nil
            return
        }
        let threshold = settings.lowSpaceThresholdGB
        let isLow = CleanupSpaceAlert.isLow(available: available, thresholdGB: threshold)
        if alerting, CleanupSpaceAlert.shouldAlert(available: available, thresholdGB: threshold, wasLow: state.wasLow) {
            onLowSpace?(available)
        }
        lowSpaceAvailable = isLow ? available : nil
        if state.wasLow != isLow {
            state.wasLow = isLow
            persist()
        }
    }

    @concurrent
    private nonisolated static func availableBytes() async -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct State: Codable {
        var enabledAt: Date?
        var lastAutomaticRunAt: Date?
        var wasLow = false
        var history: [CleanupHistoryEntry] = []
    }
}

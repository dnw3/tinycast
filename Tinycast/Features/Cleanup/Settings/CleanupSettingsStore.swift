import Foundation
import Observation

/// Disk Cleanup's preferences; the defaults here are the ones the pane shows.
@MainActor
@Observable
final class CleanupSettingsStore {
    private let defaults: UserDefaults

    var deletionMode: CleanupDeletionMode {
        didSet { defaults.set(deletionMode.rawValue, forKey: AppSettingsKey.cleanupDeletionMode.rawValue) }
    }
    /// Tilde-abbreviated, so the settings file reads the same on any account.
    var exclusions: [String] {
        didSet { defaults.set(exclusions, forKey: AppSettingsKey.cleanupExclusions.rawValue) }
    }

    /// A project untouched this long has its rebuildable folders offered.
    var projectIdleDays: Int {
        didSet { defaults.set(projectIdleDays, forKey: AppSettingsKey.cleanupProjectIdleDays.rawValue) }
    }

    /// Files at least this big are offered as large files.
    var largeFileThresholdMB: Int {
        didSet { defaults.set(largeFileThresholdMB, forKey: AppSettingsKey.cleanupLargeFileThreshold.rawValue) }
    }

    /// Grants unattended deletion, so it is switched on only in the app, after a confirmation, and
    /// never carried by a backup or the settings file.
    var scheduleEnabled: Bool {
        didSet { defaults.set(scheduleEnabled, forKey: AppSettingsKey.cleanupScheduleEnabled.rawValue) }
    }
    var scheduleInterval: CleanupScheduleInterval {
        didSet { defaults.set(scheduleInterval.rawValue, forKey: AppSettingsKey.cleanupScheduleInterval.rawValue) }
    }
    var lowSpaceAlertEnabled: Bool {
        didSet { defaults.set(lowSpaceAlertEnabled, forKey: AppSettingsKey.cleanupLowSpaceAlert.rawValue) }
    }
    var lowSpaceThresholdGB: Int {
        didSet { defaults.set(lowSpaceThresholdGB, forKey: AppSettingsKey.cleanupLowSpaceThreshold.rawValue) }
    }

    static let largeFileChoicesMB = CleanupFilePolicy.largeThresholdChoices.map { Int($0 >> 20) }

    var largeFileThreshold: Int64 { Int64(largeFileThresholdMB) << 20 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deletionMode = defaults.string(forKey: AppSettingsKey.cleanupDeletionMode.rawValue)
            .flatMap(CleanupDeletionMode.init(rawValue:)) ?? .tiered
        let idle = defaults.integer(forKey: AppSettingsKey.cleanupProjectIdleDays.rawValue)
        projectIdleDays = CleanupProjectPolicy.idleDayChoices.contains(idle) ? idle : CleanupProjectPolicy.defaultIdleDays
        let large = defaults.integer(forKey: AppSettingsKey.cleanupLargeFileThreshold.rawValue)
        largeFileThresholdMB =
            Self.largeFileChoicesMB.contains(large) ? large : Int(CleanupFilePolicy.defaultLargeThreshold >> 20)
        scheduleEnabled = defaults.bool(forKey: AppSettingsKey.cleanupScheduleEnabled.rawValue)
        scheduleInterval = defaults.string(forKey: AppSettingsKey.cleanupScheduleInterval.rawValue)
            .flatMap(CleanupScheduleInterval.init(rawValue:)) ?? .weekly
        lowSpaceAlertEnabled = defaults.object(forKey: AppSettingsKey.cleanupLowSpaceAlert.rawValue) as? Bool ?? true
        let threshold = defaults.integer(forKey: AppSettingsKey.cleanupLowSpaceThreshold.rawValue)
        lowSpaceThresholdGB =
            CleanupSpaceAlert.thresholdChoicesGB.contains(threshold) ? threshold : CleanupSpaceAlert.defaultThresholdGB
        exclusions = Self.normalize(defaults.stringArray(forKey: AppSettingsKey.cleanupExclusions.rawValue) ?? [])
    }

    /// What the scanner and the selection compare against: absolute and standardized.
    var resolvedExclusions: [String] {
        exclusions.map { ($0 as NSString).expandingTildeInPath }
    }

    func exclude(_ path: String) {
        let entry = Self.abbreviate(path)
        guard !exclusions.contains(entry) else { return }
        exclusions.append(entry)
    }

    func remove(_ entry: String) {
        exclusions.removeAll { $0 == entry }
    }

    /// One spelling per folder, so a hand-edited file cannot list one twice or as a relative path.
    static func normalize(_ entries: [String]) -> [String] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            let abbreviated = abbreviate(expanded)
            return seen.insert(abbreviated).inserted ? abbreviated : nil
        }
    }

    private static func abbreviate(_ path: String) -> String {
        ((path as NSString).standardizingPath as NSString).abbreviatingWithTildeInPath
    }
}

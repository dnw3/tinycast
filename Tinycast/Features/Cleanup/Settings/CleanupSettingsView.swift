import AppKit
import Combine
import SwiftUI

struct CleanupSettingsView: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Open Disk Cleanup") { core.cleanupCoordinator.show() }
                } label: {
                    SettingsFeatureToggleLabel(
                        anchor: .cleanupCleanup, title: "Disk Cleanup",
                        subtitle: "Finds caches, logs and build data you can remove.")
                }
            }
            .settingsAnchor(.cleanupCleanup)

            CleanupAccessSection()
            CleanupDeletionSection()
            CleanupProjectsSection()
            CleanupFilesSection()
            CleanupAutomationSection()
            FeatureCommandsSection(owner: .cleanup, anchor: .cleanupCommands)
            CleanupExclusionsSection()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.cleanup)
    }
}

/// A deliberate copy of File Search's row: each pane says what the grant buys it.
private struct CleanupAccessSection: View {
    @State private var granted = Permissions.hasFullDiskAccess()
    /// Nothing announces a grant made in System Settings, so the pane asks while it is open.
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                        Text(granted ? String(localized: "Granted") : String(localized: "Recommended"))
                    }
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    Button(granted ? String(localized: "Open…") : String(localized: "Open Privacy Settings…")) {
                        Permissions.openFullDiskAccessSettings()
                    }
                    .help("Opens Privacy & Security › Full Disk Access.")
                }
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.cleanupFullDiskAccess, "Full Disk Access")
                    Text(
                        granted
                            ? String(localized: "Disk Cleanup can reach every cache.")
                            : String(localized: "Sandboxed app caches, Messages previews and the Trash are skipped."))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(.cleanupFullDiskAccess)
        }
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        let now = Permissions.hasFullDiskAccess()
        if now != granted { granted = now }
    }
}

private struct CleanupDeletionSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        @Bindable var settings = core.cleanupSettings
        return Section {
            Picker(selection: $settings.deletionMode) {
                Text("Delete rebuildable items").tag(CleanupDeletionMode.tiered)
                Text("Move everything to the Trash").tag(CleanupDeletionMode.trashOnly)
            } label: {
                SettingsRowTitle(.cleanupDeletion, "Cleaned items")
            }
        } header: {
            SettingsSectionHeader(.cleanupDeletion)
        } footer: {
            Text(
                settings.deletionMode == .tiered
                    ? String(localized: "Rebuildable caches and logs are deleted for good; the rest goes to the Trash.")
                    : String(localized: "Space comes back only when you empty the Trash.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct CleanupExclusionsSection: View {
    @Environment(AppCore.self) private var core
    @State private var missing: Set<String> = []

    var body: some View {
        let settings = core.cleanupSettings
        Section {
            ForEach(settings.exclusions, id: \.self) { entry in
                SettingsScopeRow(
                    scope: entry, path: (entry as NSString).expandingTildeInPath, isMissing: missing.contains(entry)
                ) {
                    settings.remove(entry)
                }
            }
            Button("Add…", action: add)
                .help(String(localized: "Choose folders Disk Cleanup never scans."))
        } header: {
            SettingsSectionHeader(.cleanupExclusions)
        } footer: {
            Text("Add one from a row’s actions with Don’t Scan This.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.exclusions) { _, _ in refreshMissing() }
    }

    private func refreshMissing() {
        missing = Set(
            core.cleanupSettings.exclusions.filter {
                !FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath)
            })
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose folders Disk Cleanup never scans.")
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { core.cleanupSettings.exclude(url.path) }
    }
}

private struct CleanupProjectsSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        @Bindable var settings = core.cleanupSettings
        return Section {
            Picker(selection: $settings.projectIdleDays) {
                ForEach(CleanupProjectPolicy.idleDayChoices, id: \.self) { days in
                    Text(String(localized: "\(days) days")).tag(days)
                }
            } label: {
                SettingsRowTitle(.cleanupProjects, "Consider a project idle after")
            }
        } header: {
            SettingsSectionHeader(.cleanupProjects)
        } footer: {
            Text(
                String(localized: "Git-tracked folders, projects in use and Terraform state are never offered.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct CleanupFilesSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        @Bindable var settings = core.cleanupSettings
        return Section {
            Picker(selection: $settings.largeFileThresholdMB) {
                ForEach(CleanupSettingsStore.largeFileChoicesMB, id: \.self) { megabytes in
                    Text(Int64(megabytes << 20).formatted(.byteCount(style: .file))).tag(megabytes)
                }
            } label: {
                SettingsRowTitle(.cleanupFiles, "List files larger than")
            }
        } header: {
            SettingsSectionHeader(.cleanupFiles)
        } footer: {
            Text(
                String(localized: "Searches Downloads, Desktop, Documents and Movies. Nothing is preselected.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct CleanupAutomationSection: View {
    @Environment(AppCore.self) private var core

    private var scheduleBinding: Binding<Bool> {
        Binding(
            get: { core.cleanupSettings.scheduleEnabled },
            set: { core.cleanupCoordinator.setScheduleEnabled($0) })
    }

    var body: some View {
        @Bindable var settings = core.cleanupSettings
        let schedule = core.cleanupSchedule
        return Section {
            Toggle(isOn: scheduleBinding) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.cleanupAutomation, "Clean up automatically")
                    Text(String(localized: "Deletes only items marked safe, while your Mac is idle."))
                        .foregroundStyle(.secondary)
                }
            }
            Picker(selection: $settings.scheduleInterval) {
                Text("Every day").tag(CleanupScheduleInterval.daily)
                Text("Every week").tag(CleanupScheduleInterval.weekly)
                Text("Every month").tag(CleanupScheduleInterval.monthly)
            } label: {
                SettingsRowTitle(.cleanupAutomation, "How often")
            }
            .settingsEnabled(settings.scheduleEnabled)
            Toggle(isOn: $settings.lowSpaceAlertEnabled) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.cleanupAutomation, "Warn when free space is low")
                    Text(String(localized: "Alerts once and adds Free Up Space to the menu bar."))
                        .foregroundStyle(.secondary)
                }
            }
            Picker(selection: $settings.lowSpaceThresholdGB) {
                ForEach(CleanupSpaceAlert.thresholdChoicesGB, id: \.self) { gigabytes in
                    Text(Int64(gigabytes * 1_000_000_000).formatted(.byteCount(style: .file))).tag(gigabytes)
                }
            } label: {
                SettingsRowTitle(.cleanupAutomation, "Below")
            }
            .settingsEnabled(settings.lowSpaceAlertEnabled)
            LabeledContent {
                Button("Clear History") { schedule.clearHistory() }
                    .settingsEnabled(!schedule.history.isEmpty)
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.cleanupAutomation, "History")
                    Text(historySummary(schedule))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(.cleanupAutomation)
        }
    }

    private func historySummary(_ schedule: CleanupScheduleStore) -> String {
        guard let last = schedule.lastRun else { return String(localized: "Nothing cleaned yet.") }
        let total = CleanupCoordinator.format(schedule.totalFreed)
        let date = last.date.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "\(total) freed in \(schedule.history.count) runs · last on \(date)")
    }
}

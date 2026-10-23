import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var diskUsage: Int64?
    /// With the feature off a clear leaves `items` empty either way, so it bumps this instead.
    @State private var clears = 0

    private var usageKey: UsageKey {
        UsageKey(
            count: core.clipboardStore.items.count, newest: core.clipboardStore.items.first?.id,
            clears: clears)
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.clipboardEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .clipboardClipboard, title: "Enable Clipboard History",
                        subtitle: "Keep copied items ready to reuse.")
                }
            }
            .settingsAnchor(.clipboardClipboard)

            FeatureCommandsSection(owner: .clipboard, anchor: .clipboardCommands)
                .settingsEnabled(settings.clipboardEnabled)

            Section {
                Picker(selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                } label: {
                    SettingsRowTitle(.clipboardHistory, "Keep history for")
                }
                Toggle(isOn: $settings.clipboardTextSearchEnabled) {
                    SettingsRowTitle(.clipboardHistory, "Search text in images and PDFs")
                    Text("Recognized on this Mac while idle.")
                }
                Picker(selection: $settings.clipboardDefaultAction) {
                    ForEach(ClipboardDefaultAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                } label: {
                    SettingsRowTitle(.clipboardHistory, "Default action")
                    Text("↵ does this, and Paste takes its shortcut.")
                }
            } header: {
                SettingsSectionHeader(.clipboardHistory)
            }
            .settingsEnabled(settings.clipboardEnabled)

            DisabledApplicationsSection(
                bundleIDs: $settings.clipboardDisabledApps,
                anchor: .clipboardDisabledApplications,
                footer: String(localized: "Copies from these apps aren't recorded.")
            )
            .settingsEnabled(settings.clipboardEnabled)

            Section {
                LabeledContent {
                    HStack {
                        if let diskUsage {
                            Text("Uses \(diskUsage.formatted(.byteCount(style: .file)))")
                                .foregroundStyle(.secondary)
                        }
                        Button("Clear…", role: .destructive) {
                            Task {
                                await core.clipboardCoordinator.deleteAllClips()
                                clears += 1
                            }
                        }
                    }
                } label: {
                    SettingsRowTitle(.clipboardDisabledApplications, "Clear history")
                    Text("Removes every item in the history.")
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipboard)
        .task(id: usageKey) {
            let store = core.clipboardStore
            let (database, images) = (store.dbURL, store.imagesDir)
            let usage = await Task.detached(priority: .utility) {
                ClipboardStore.diskUsage(databaseAt: database, imagesIn: images)
            }.value
            guard !Task.isCancelled else { return }
            diskUsage = usage
        }
    }
}

/// Recounted when the history gains, loses or reorders a row, never on a timer.
private struct UsageKey: Equatable {
    let count: Int
    let newest: UUID?
    let clears: Int
}

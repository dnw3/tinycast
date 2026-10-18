import AppKit
import SwiftUI

struct CaptureSettingsView: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.settings
        Form {
            Section {
                Toggle(
                    isOn: Binding(get: { store.preferences.enabled }, set: { coordinator.setEnabled($0) })
                ) {
                    SettingsFeatureToggleLabel(
                        anchor: .captureCapture, title: "Enable Capture",
                        subtitle: String(localized: "Capture, annotate, pin and extract text from screenshots."))
                }
            }
            .settingsAnchor(.captureCapture)
            Group {
                Section {
                    Picker(selection: $store.preferences.format) {
                        ForEach(CaptureRenderer.exportFormats, id: \.self) {
                            Text(LocalizedStringKey($0.title)).tag($0.rawValue)
                        }
                    } label: {
                        SettingsRowTitle(.captureOutput, "Output format")
                    }
                    LabeledContent {
                        Button("Show in Finder") { coordinator.revealQuickSaveFolder() }
                        Button("Choose…") { coordinator.chooseQuickSaveFolder() }
                        Button("Use Default") { coordinator.resetQuickSaveFolder() }
                    } label: {
                        SettingsRowTitle(.captureOutput, "Quick save folder")
                        Text((coordinator.quickSaveDirectory.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Button("Customize Toolbar…") { coordinator.toolbarCustomization.show(coordinator) }
                    Toggle("Close after copying", isOn: $store.preferences.closeAfterCopy)
                    Toggle(isOn: $store.showsCompletionThumbnail) {
                        Text("Show completion thumbnail")
                        Text("Click to reopen, or drag the final file.")
                    }
                    .onChange(of: store.showsCompletionThumbnail) { _, enabled in
                        if !enabled { coordinator.completionThumbnail.close() }
                    }
                    Toggle("Include mouse pointer", isOn: $store.preferences.includesCursor)
                } header: {
                    SettingsSectionHeader(.captureOutput)
                }
                Section {
                    Picker(selection: $store.preferences.axis) {
                        Text("Vertical").tag(CaptureDocument.Axis.vertical)
                        Text("Horizontal").tag(CaptureDocument.Axis.horizontal)
                    } label: {
                        SettingsRowTitle(.captureScrolling, "Direction")
                    }
                    Picker("Automatic scroll speed", selection: $store.preferences.scrollSpeed) {
                        Text("Slow").tag(0); Text("Medium").tag(1); Text("Fast").tag(2)
                    }
                } header: {
                    SettingsSectionHeader(.captureScrolling)
                }
                Section {
                    Picker("Keep screenshots", selection: $store.preferences.retentionDays) {
                        Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30)
                    }
                    Picker("Storage limit", selection: $store.preferences.maximumHistoryMB) {
                        Text("128 MB").tag(128); Text("512 MB").tag(512); Text("1 GB").tag(1024)
                    }
                    Toggle(isOn: $store.keepsOriginals) {
                        SettingsRowTitle(.captureHistory, "Keep editable originals")
                    }
                    Button("Open Capture History") { coordinator.open(.captureHistory) }
                } header: {
                    SettingsSectionHeader(.captureHistory)
                } footer: {
                    Text("Editable originals include the image before redaction, and are never imported from a backup.")
                }
                CaptureUploadSettingsView()
                FeatureCommandsSection(owner: .capture, anchor: .captureCommands)
            }
            .settingsEnabled(store.preferences.enabled)
            Section {
                permissionRow(
                    anchor: .capturePermissions, title: "Screen Recording",
                    subtitle: String(localized: "Captures the screen and records video."),
                    granted: CGPreflightScreenCaptureAccess(), open: coordinator.openScreenPermission)
                permissionRow(
                    anchor: .capturePermissions, title: "Accessibility",
                    subtitle: String(localized: "Auto Scroll, element picking and keystroke display."),
                    granted: Permissions.isAccessibilityTrusted(), open: Permissions.openAccessibilitySettings)
            } header: {
                SettingsSectionHeader(.capturePermissions)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.capture)
    }

    private func permissionRow(
        anchor: SettingsAnchor, title: String, subtitle: String, granted: Bool, open: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(granted ? String(localized: "Granted") : String(localized: "Not granted"))
                }
                .foregroundStyle(granted ? Color.green : Color.orange)
                Button(granted ? String(localized: "Open…") : String(localized: "Grant Access…"), action: open)
            }
        } label: {
            SettingsRowTitle(anchor, title)
            Text(subtitle)
        }
    }
}

import AppKit
import SwiftUI

struct CaptureSettingsView: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.settings
        Form {
            Section {
                Toggle(isOn: Binding(get: { store.preferences.enabled }, set: coordinator.setEnabled)) {
                    SettingsRowTitle(.captureCapture, "Enable Capture")
                    Text("Capture, annotate, pin and extract text from screenshots.")
                }
                Button("Capture Screenshot") { coordinator.open(.captureScreenshot) }.disabled(
                    !store.preferences.enabled)
            } header: {
                SettingsSectionHeader(.captureCapture)
            }
            Section {
                Picker(selection: $store.preferences.format) {
                    ForEach(CaptureRenderer.exportFormats, id: \.self) {
                        Text(LocalizedStringKey($0.title)).tag($0.rawValue)
                    }
                } label: {
                    SettingsRowTitle(.captureOutput, "Output format")
                }
                LabeledContent("Quick save folder") {
                    Text(coordinator.quickSaveDirectory.path).lineLimit(1).truncationMode(.middle)
                    Button("Show in Finder") { coordinator.revealQuickSaveFolder() }
                    Button("Choose…") { coordinator.chooseQuickSaveFolder() }
                    Button("Reset") { coordinator.resetQuickSaveFolder() }
                }
                Button("Customize Toolbar…") { coordinator.toolbarCustomization.show(coordinator) }
                Toggle("Close after copying", isOn: $store.preferences.closeAfterCopy)
                Toggle("Show completion thumbnail", isOn: $store.showsCompletionThumbnail)
                    .help(
                        String(
                            localized:
                                "Click to reopen, or drag the final file. Dismisses after 8 seconds when not hovered."
                        )
                    )
                    .onChange(of: store.showsCompletionThumbnail) { _, enabled in
                        if !enabled { coordinator.completionThumbnail.close() }
                    }
                Toggle("Include mouse pointer", isOn: $store.preferences.includesCursor)
            } header: {
                SettingsSectionHeader(.captureOutput)
            } footer: {
                Text(
                    String(
                        localized:
                            "Copies use PNG at original resolution. The Save button asks for a location. ⌘S uses the quick save folder; ⇧⌘S opens Save As. Save large images as PNG when copying exceeds the memory budget."
                    )
                )
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
            } footer: {
                Text("Starts in manual mode. Auto Scroll is enabled only when you click it during a capture.")
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
                Text(
                    String(
                        localized:
                            "Editable originals include the image before redaction. This choice is never imported from a backup. Drafts remain until you delete them."
                    )
                )
            }
            CaptureUploadSettingsView()
            FeatureCommandsSection(owner: .capture, anchor: .captureCommands)
            Section {
                LabeledContent(
                    String(localized: "Screen Recording"), value: CGPreflightScreenCaptureAccess() ? String(localized: "Allowed") : String(localized: "Required"))
                Button("Screen Recording Settings…") { coordinator.openScreenPermission() }
                LabeledContent(
                    "Accessibility",
                    value: Permissions.isAccessibilityTrusted()
                        ? String(localized: "Allowed") : String(localized: "Auto Scroll, Elements and Keys")
                )
                Button("Accessibility Settings…") { Permissions.openAccessibilitySettings() }
            } header: {
                SettingsSectionHeader(.capturePermissions)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.capture)
    }
}

import AppKit
import SwiftUI

/// The config the core is given, links masked, to read or to paste into a report.
struct ProxyConfigViewer: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    @State private var text = ""
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "Generated Config",
                subtitle: "What the core is given, with subscription links masked."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Theme.Spacing.dialogInset)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(Theme.Spacing.md)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
                .padding(.horizontal, Theme.Spacing.dialogInset)
            }

            Divider()
                .padding(.top, Theme.Spacing.dialogInset)
            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                Button("Copy", action: copy)
                    .buttonStyle(.modalAction(.standard))
                    .disabled(failure != nil || text.isEmpty)
                Button("Done", action: close)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 680, height: 620)
        .settingsEditorPanelSurface()
        .onAppear(perform: load)
    }

    private func load() {
        do {
            text = try manager.previewConfig(linkPlaceholder: String(localized: "<subscription link>"))
        } catch let invalid as ProxyInvalidProfile {
            failure = ProxyFailure.invalidProfile(invalid.problems).message(in: manager.store.profile)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        core.showMessage(String(localized: "Config copied"))
    }
}

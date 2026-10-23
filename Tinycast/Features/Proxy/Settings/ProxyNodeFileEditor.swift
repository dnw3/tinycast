import SwiftUI

/// A local node file edited where it lives; saving has a connected core reread it at once.
struct ProxyNodeFileEditor: View {
    let file: URL
    let manager: ProxyManager
    let close: () -> Void
    @State private var text = ""
    @State private var isLoaded = false
    @State private var error: String?
    @State private var outline: ProxyNodeFileOutline?

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "\(file.lastPathComponent)", subtitle: "\((file.path as NSString).abbreviatingWithTildeInPath)"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                .writingToolsBehavior(.disabled)
                .settingsEditorTextArea(height: 420)
                .padding(.horizontal, Theme.Spacing.dialogInset)
                .disabled(!isLoaded)

            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(
                            "Only the nodes under `proxies:` are read, or one share link per line; the rest is left out."
                        )
                        if let outline {
                            Text(
                                [outline.nodesTitle, outline.unusedSummary].compactMap(\.self).joined(
                                    separator: " · "))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.vertical, Theme.Spacing.md)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .disabled(!isLoaded)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 680, height: 640)
        .settingsEditorPanelSurface()
        .onAppear(perform: load)
    }

    private func load() {
        guard !isLoaded else { return }
        do {
            text = try String(contentsOf: file, encoding: .utf8)
            outline = ProxyNodeFileOutline(text: text)
            isLoaded = true
        } catch {
            self.error = String(localized: "The file could not be read: \(error.localizedDescription)")
        }
    }

    /// Writes through a symlink to its target and keeps the file's permissions, which hold secrets.
    private func save() {
        let target = file.resolvingSymlinksInPath()
        let files = FileManager.default
        let permissions = try? files.attributesOfItem(atPath: target.path)[.posixPermissions]
        do {
            try Data(text.utf8).write(to: target, options: .atomic)
            if let permissions {
                try files.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
        } catch {
            self.error = String(localized: "The file could not be saved: \(error.localizedDescription)")
            return
        }
        manager.reloadFile(at: file)
        close()
    }
}

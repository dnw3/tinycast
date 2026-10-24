import AppKit
import SwiftUI

/// A source being added or changed; a new subscription may arrive with its link already pasted.
struct ProxySourceDraft {
    var source: ProxySource
    var isNew: Bool
    var link: String
    var connectsWhenAdded = false

    static func newSubscription(link: String, connects: Bool) -> ProxySourceDraft {
        ProxySourceDraft(
            source: .subscription(id: UUID(), name: ""), isNew: true, link: link, connectsWhenAdded: connects)
    }

    /// The link is read from the keychain here, once, rather than each time the editor redraws.
    @MainActor
    static func existing(_ source: ProxySource, in store: ProxyStore) -> ProxySourceDraft {
        let link = source.kind == .subscription ? store.subscriptionURL(for: source.id) : nil
        return ProxySourceDraft(source: source, isNew: false, link: link ?? "")
    }
}

/// Names a source, holds its link or file, and trims and renames the nodes it brings.
struct ProxySourceEditor: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    private let isNew: Bool
    private let connectsWhenAdded: Bool
    @State private var source: ProxySource
    @State private var link: String
    @State private var error: String?
    @State private var outline: ProxyNodeFileOutline?
    /// Wide enough for a link; one width, so the fields line up whatever their labels.
    private let fieldWidth: CGFloat = 430

    init(draft: ProxySourceDraft, manager: ProxyManager, close: @escaping () -> Void) {
        self.manager = manager
        self.close = close
        isNew = draft.isNew
        connectsWhenAdded = draft.connectsWhenAdded
        _source = State(initialValue: draft.source)
        _link = State(initialValue: draft.link)
    }

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var isSubscription: Bool { source.kind == .subscription }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.dialogInset)
                .padding(.top, Theme.Spacing.dialogInset)
                .padding(.bottom, Theme.Spacing.xl)

            Form {
                identity
                contents
                filters
                renames
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                if !isNew {
                    Button("Delete…") {
                        close()
                        coordinator.deleteSource(source.id)
                    }
                    .buttonStyle(.modalAction(.destructive))
                }
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 640)
        .settingsEditorPanelSurface()
        .task(id: source.kind) {
            guard case .file(let path) = source.kind else { return }
            outline = await ProxyNodeFileReader.outline(
                of: URL(filePath: (path as NSString).expandingTildeInPath))
        }
    }

    private var title: LocalizedStringResource {
        switch (isNew, isSubscription) {
        case (true, true): "Add Subscription"
        case (true, false): "Add Local File"
        case (false, true): "Edit Subscription"
        case (false, false): "Edit Local File"
        }
    }

    private var subtitle: LocalizedStringResource {
        isSubscription
            ? "Paste the link your provider gave you. Clash files and share links both work."
            : "The file is read where it is, each time the proxy connects."
    }

    // MARK: - Sections

    private var identity: some View {
        Section {
            SettingsEditorField("Name") {
                TextField("Name", text: $source.name, prompt: Text(namePrompt))
                    .settingsEditorTextField()
                    .frame(width: fieldWidth)
            }
            switch source.kind {
            case .subscription:
                SettingsEditorField("Link") {
                    RevealableSecureField(
                        title: String(localized: "Link"), text: $link, prompt: Text(verbatim: "https://…")
                    )
                    .settingsEditorTextField()
                    .frame(width: fieldWidth)
                }
            case .file(let path):
                SettingsEditorField("File") {
                    HStack(spacing: Theme.Spacing.md) {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Show in Finder") {
                            let url = URL(filePath: (path as NSString).expandingTildeInPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .frame(width: fieldWidth)
                }
            }
            if !isNew, let loaded = manager.snapshot?.sources[source.id] {
                SettingsEditorField("In the Pool") {
                    Text(String(localized: "\(loaded.nodes.count) nodes"))
                    .foregroundStyle(.secondary)
                    .frame(width: fieldWidth, alignment: .leading)
                }
            }
        } footer: {
            if isSubscription {
                Text("The link stays in your login Keychain and never leaves with a settings backup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the core takes from a file, so its groups and rules are not looked for in vain.
    @ViewBuilder private var contents: some View {
        if case .file = source.kind {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(outline?.nodesTitle ?? String(localized: "Reading the file…"))
                    if let unused = outline?.unusedSummary {
                        Text(unused)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("In This File")
            } footer: {
                Text(
                    "Only nodes are taken from a file; strategies, routes and rules are set on their own pages."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var filters: some View {
        Section {
            SettingsEditorField("Prefix") {
                TextField(
                    "Prefix", text: $source.prefix,
                    prompt: Text(ProxyPrompt.example(String(localized: "Work · ")))
                )
                .settingsEditorTextField()
                .frame(width: fieldWidth)
            }
            SettingsEditorField("Keep only") {
                TextField("Keep only", text: $source.include, prompt: Text(ProxyPrompt.example("HK|SG|JP")))
                    .settingsEditorTextField()
                    .frame(width: fieldWidth)
            }
            SettingsEditorField("Leave out") {
                TextField(
                    "Leave out", text: $source.exclude,
                    prompt: Text(ProxyPrompt.example(ProxySource.defaultExclude))
                )
                .settingsEditorTextField()
                .frame(width: fieldWidth)
            }
        } header: {
            Text("Nodes")
        } footer: {
            Text(
                "Patterns are regular expressions matched against the names the source itself uses. The prefix keeps two sources with the same names apart."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var renames: some View {
        Section {
            ForEach(source.renames.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.md) {
                    TextField(
                        "Name Pattern", text: $source.renames[index].pattern,
                        prompt: Text(ProxyPrompt.example("香港"))
                    )
                    .settingsEditorTextField()
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField(
                        "Replacement", text: $source.renames[index].replacement,
                        prompt: Text(ProxyPrompt.example("HK"))
                    )
                    .settingsEditorTextField()
                    Button {
                        source.renames.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Remove Rename"))
                }
            }
            Button("Add Rename") { source.renames.append(ProxyRename(pattern: "", replacement: "")) }
        } header: {
            Text("Renames")
        } footer: {
            Text("Applied in order, before the prefix. Strategies match the names as renamed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var namePrompt: String {
        switch source.kind {
        case .subscription: Self.name(fromLink: link) ?? String(localized: "My Provider")
        case .file(let path): URL(filePath: path).deletingPathExtension().lastPathComponent
        }
    }

    /// A link's host without `www.`, the name a new subscription takes when none is typed.
    private static func name(fromLink link: String) -> String? {
        guard ProxyText.isWebURL(link.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines))?.host
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Saving

    private func save() {
        var source = source
        source.name = source.name.trimmingCharacters(in: .whitespaces)
        if source.name.isEmpty { source.name = namePrompt }
        source.renames.removeAll { $0.pattern.isEmpty }
        var trimmedLink: String?
        if isSubscription {
            let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ProxyText.isWebURL(link) else {
                error = String(localized: "Enter the subscription link, starting with https://.")
                return
            }
            trimmedLink = link
        }
        var candidate = manager.store.profile
        if let index = candidate.sources.firstIndex(where: { $0.id == source.id }) {
            candidate.sources[index] = source
        } else {
            candidate.sources.append(source)
        }
        if let problem = candidate.problems.first(where: { $0.subject == .source(source.id) }) {
            error = problem.message(in: candidate)
            return
        }
        if let failure = coordinator.saveSource(source, link: trimmedLink, connects: connectsWhenAdded) {
            error = failure
            return
        }
        close()
    }
}

/// The starter file a new local node file begins as.
@MainActor
enum ProxyNodeFilePicker {
    /// Creates `Nodes/<name>.yaml` from the template and adds it as a source; nil if it cannot.
    static func newFile(coordinator: ProxyCoordinator, store: ProxyStore) -> URL? {
        let manager = FileManager.default
        let directory = store.nodesDirectory
        let base = String(localized: "My Nodes")
        let names = [base] + (2...99).map { "\(base) \($0)" }
        guard
            let url = names.lazy.map({ directory.appending(path: "\($0).yaml") })
                .first(where: { !manager.fileExists(atPath: $0.path) })
        else { return nil }
        do {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(template.utf8).write(to: url, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            coordinator.reportNodeFileFailure(error)
            return nil
        }
        coordinator.addFileSource(url)
        return url
    }

    static let template = """
        # Each node goes under `proxies`, in the same form a Clash subscription uses.
        # Share links work too: replace this file with one ss://, vmess:// or trojan:// link per line.
        proxies:
          # - name: Home
          #   type: ss
          #   server: home.example.com
          #   port: 8388
          #   cipher: aes-128-gcm
          #   password: change-me

        """
}

import SwiftUI

/// Where the nodes come from: each subscription and local file, and the way to add another.
struct ProxySourcesPane: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    @State private var link = ""

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    private static let cardWidth = 300.0

    var body: some View {
        ProxyPage {
            ProxyNote(
                text: String(
                    localized:
                        "Subscriptions and local files only provide nodes. Strategies and routing are set up here; the groups and rules a subscription carries are not used."
                ))
            if let duplicates = manager.snapshot?.duplicates, !duplicates.isEmpty {
                ProxyNote(
                    text: String(
                        localized:
                            "\(duplicates.count) node names appear in more than one source; only the first of each can be picked.")
                ) {
                    Button("Add Prefixes") { coordinator.prefixDuplicates() }
                }
            }
            HStack {
                ProxySectionHeader(title: String(localized: "Sources"))
                if profile.hasSubscriptions {
                    Button("Update All") { coordinator.updateSubscriptions() }
                        .disabled(!manager.isRunning || !manager.updatingSources.isEmpty)
                }
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Theme.Spacing.xl, alignment: .top)],
                alignment: .leading, spacing: Theme.Spacing.xl
            ) {
                ForEach(profile.sources) { source in
                    ProxySourceCard(manager: manager, source: source)
                }
                addCard
            }
        }
    }

    private var addCard: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Add a Subscription").font(.headline)
                Text("Paste the link your provider gave you; the name is filled in from its address.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    // Verbatim: a literal prompt is read as Markdown, which would style the URL.
                    TextField("Subscription Link", text: $link, prompt: Text(verbatim: "https://…"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(!ProxyText.isWebURL(link.trimmingCharacters(in: .whitespaces)))
                }
                HStack(spacing: Theme.Spacing.lg) {
                    Button("Import Local File…") { coordinator.importNodeFiles() }
                    Button("New Node File…") {
                        if let url = ProxyNodeFilePicker.newFile(coordinator: coordinator, store: manager.store) {
                            openEditor(.nodeFile(url))
                        }
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private func add() {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        guard ProxyText.isWebURL(trimmed) else { return }
        openEditor(.source(.newSubscription(link: trimmed, connects: false)))
        link = ""
    }
}

/// One source: its nodes, its plan's usage and expiry, whether it is in the pool, and its actions.
private struct ProxySourceCard: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    let source: ProxySource

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var loaded: ProxySnapshot.Source? { manager.snapshot?.sources[source.id] }

    var body: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(source.name).font(.headline).lineLimit(1)
                    Text(source.kind == .subscription ? String(localized: "Subscription") : String(localized: "Local File"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Capsule().fill(Theme.Colors.controlSurface))
                    Spacer()
                    Toggle(isOn: enabled) { Text("Use \(source.name)") }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                usage
                actions
            }
        }
        .proxyDimmed(!source.isEnabled)
        .contextMenu {
            Button("Show Nodes…") { openEditor(.nodes(source.id)) }
                .disabled(loaded == nil)
            Divider()
            Button("Delete…", role: .destructive) { coordinator.deleteSource(source.id) }
        }
    }

    @ViewBuilder private var usage: some View {
        if source.kind == .subscription, let usage = loaded?.usage, usage.total > 0 {
            let used = usage.upload + usage.download
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView(value: Double(min(used, usage.total)), total: Double(usage.total))
                    .tint(Double(used) / Double(usage.total) > 0.9 ? Theme.Colors.warning : Theme.Colors.progress)
                HStack {
                    Text("\(used.formatted(.byteCount(style: .file))) of \(usage.total.formatted(.byteCount(style: .file))) used")
                    Spacer()
                    if usage.expire > 0 {
                        let date = Date(timeIntervalSince1970: TimeInterval(usage.expire))
                        Text("Expires \(date.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else if case .file(let path) = source.kind {
            Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            if source.kind == .subscription {
                if manager.updatingSources.contains(source.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update") { Task { await manager.updateSource(source.id) } }
                        .disabled(!manager.isRunning || !source.isEnabled)
                }
            }
            if case .file(let path) = source.kind {
                Button("Edit File…") { openEditor(.nodeFile(URL(filePath: (path as NSString).expandingTildeInPath))) }
            }
            Button("Edit…") { openEditor(.source(.existing(source, in: manager.store))) }
            Button("Show Nodes") { openEditor(.nodes(source.id)) }
                .disabled(loaded == nil)
        }
        .controlSize(.small)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { source.isEnabled },
            set: { value in
                coordinator.update { profile in
                    guard let index = profile.sources.firstIndex(where: { $0.id == source.id }) else { return }
                    profile.sources[index].isEnabled = value
                }
            })
    }

    private var summary: String {
        guard source.isEnabled else { return String(localized: "Not in the node pool") }
        if source.kind == .subscription, !manager.store.hasSubscriptionURL(for: source.id) {
            return String(localized: "No link; edit the source to add one")
        }
        guard let loaded else { return String(localized: "Loaded once connected") }
        let nodes = String(localized: "\(loaded.nodes.count) nodes")
        guard let updated = loaded.updatedAt else { return nodes }
        return nodes + " · " + String(localized: "Updated \(updated.formatted(.relative(presentation: .named)))")
    }
}

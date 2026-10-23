import SwiftUI

/// The node pool as the connected core holds it, by region, with each node's source and delay.
struct ProxyNodeListViewer: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    @State private var query = ""
    @State private var source: UUID?

    init(manager: ProxyManager, source: UUID?, close: @escaping () -> Void) {
        self.manager = manager
        self.close = close
        _source = State(initialValue: source)
    }

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var profile: ProxyProfile { manager.store.profile }
    private var pooled: [ProxySource] { profile.sources.filter(\.isEnabled) }

    private struct Region: Identifiable {
        let id: String
        let title: String
        let nodes: [ProxySnapshot.Node]
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(title: "Node Pool", subtitle: "\(subtitle)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.dialogInset)
                .padding(.top, Theme.Spacing.dialogInset)
                .padding(.bottom, Theme.Spacing.xl)

            HStack(spacing: Theme.Spacing.md) {
                TextField("Search Nodes", text: $query, prompt: Text("Search by name, region or protocol"))
                    .settingsEditorTextField()
                if pooled.count > 1 {
                    Picker("Source", selection: $source) {
                        Text("All Sources").tag(UUID?.none)
                        Divider()
                        ForEach(pooled) { source in
                            Text(source.name).tag(UUID?.some(source.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.md)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                if manager.isTestingSources {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Test All") { coordinator.testAllNodes() }
                        .buttonStyle(.modalAction(.standard))
                        .disabled(!manager.isRunning)
                }
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 640, height: 620)
        .settingsEditorPanelSurface()
        .task { await manager.refresh() }
    }

    @ViewBuilder private var content: some View {
        let regions = regions
        if manager.snapshot == nil {
            ContentUnavailableView(
                "Not Connected", systemImage: "network.slash",
                description: Text("The core reads the sources when it connects; their nodes show here then."))
        } else if regions.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(regions) { region in
                    Section(region.title) {
                        ForEach(region.nodes) { node in
                            row(node)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var subtitle: String {
        guard let snapshot = manager.snapshot else {
            return String(localized: "Connect the proxy to see the nodes its sources bring.")
        }
        let count = snapshot.nodes.count
        let nodes = String(localized: "\(count) nodes")
        return String(localized: "\(nodes) from \(pooled.count) sources. Strategies pick from them.")
    }

    /// In each source's own order, as the provider lists them.
    private var regions: [Region] {
        guard let snapshot = manager.snapshot else { return [] }
        let typed = query.trimmingCharacters(in: .whitespaces)
        var byRegion: [ProxyRegion?: [ProxySnapshot.Node]] = [:]
        for candidate in pooled where source == nil || candidate.id == source {
            for name in snapshot.sources[candidate.id]?.nodes ?? [] {
                guard let node = snapshot.nodes[name], node.source == candidate.id,
                    typed.isEmpty
                        || [node.name, node.kind, node.region?.title ?? ProxyRegion.otherTitle].contains(
                            where: {
                                $0.localizedStandardContains(typed)
                            })
                else { continue }
                byRegion[node.region, default: []].append(node)
            }
        }
        let order: [ProxyRegion?] = ProxyRegion.allCases.map(Optional.some) + [nil]
        return order.compactMap { region in
            guard let nodes = byRegion[region] else { return nil }
            let title = region?.label ?? ProxyRegion.otherTitle
            return Region(id: region?.rawValue ?? "other", title: "\(title) · \(nodes.count)", nodes: nodes)
        }
    }

    private func row(_ node: ProxySnapshot.Node) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text(node.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: Theme.Spacing.md)
            Text(details(of: node))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(node.latest.label ?? "–")
                .font(.callout.monospacedDigit())
                .foregroundStyle(ProxyPaletteRow.Tone(node.latest).color)
                .frame(minWidth: 64, alignment: .trailing)
                .fixedSize()
        }
        .contextMenu {
            Button("Test Delay") { coordinator.testNode(node.name) }
                .disabled(!manager.isRunning)
            Button("Copy Name") { coordinator.copyNodeName(node.name) }
        }
    }

    private func details(of node: ProxySnapshot.Node) -> String {
        var parts = [node.kind]
        if node.supportsUDP { parts.append("UDP") }
        if source == nil, pooled.count > 1, let name = pooled.first(where: { $0.id == node.source })?.name {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }
}

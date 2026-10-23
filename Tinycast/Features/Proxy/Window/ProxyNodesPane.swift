import SwiftUI

/// The strategies as tabs: what each picks now, what it can pick, and every node the sources bring.
struct ProxyNodesPane: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    @Bindable var state: ProxyWindowState

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        ProxyPage {
            tabs
            switch tab {
            case .allNodes: ProxyAllNodes(manager: manager)
            case .strategy(let id):
                if let strategy = profile.strategy(id) {
                    ProxyStrategyDetail(manager: manager, strategy: strategy)
                }
            }
        }
    }

    private var tab: ProxyWindowState.NodesTab {
        switch state.nodesTab {
        case .strategy(let id) where profile.strategy(id) != nil: .strategy(id)
        case .allNodes: .allNodes
        default: .strategy(profile.defaultStrategy)
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(profile.strategies) { strategy in
                    tabButton(.strategy(strategy.id)) {
                        ProxyTintDot(tint: strategy.tint, size: Theme.Size.colorDot)
                        Text(strategy.name)
                        if let flag = manager.snapshot?.node(reachedBy: strategy.id, in: profile)?.flag {
                            Text(flag)
                        }
                    }
                }
                tabButton(.allNodes) {
                    Text("All Nodes")
                    if let count = manager.snapshot?.nodes.count { Text(count, format: .number).foregroundStyle(.secondary) }
                }
                Button {
                    openEditor(.strategy(ProxyStrategyDraft.new(in: profile, forRoute: nil)))
                } label: {
                    Label("New Strategy", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .scrollIndicators(.never)
    }

    private func tabButton<Label: View>(
        _ target: ProxyWindowState.NodesTab, @ViewBuilder label: () -> Label
    ) -> some View {
        let selected = tab == target
        return Button {
            state.nodesTab = target
        } label: {
            HStack(spacing: Theme.Spacing.sm) { label() }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule().fill(selected ? Theme.Colors.selection : Theme.Colors.cardFill))
                .overlay(Capsule().strokeBorder(selected ? Theme.Colors.border : Theme.Colors.cardStroke))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One strategy: its kind, where it exits now, and the options it picks among.
private struct ProxyStrategyDetail: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    let strategy: ProxyStrategy

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var group: ProxySnapshot.Group? { manager.snapshot?.strategies[strategy.id] }

    var body: some View {
        header
        if strategy.kind != .select {
            ProxyNote(text: strategy.kind.explanation)
        }
        if let group {
            options(group)
        } else {
            ProxyNote(text: String(localized: "Connect to see the nodes this strategy can pick."))
        }
    }

    private var header: some View {
        let reach = manager.snapshot?.reach(from: strategy.id, in: profile)
        return ProxyCard {
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProxyTintDot(tint: strategy.tint, size: Theme.Size.colorDot)
                        Text(strategy.name).font(.title3.weight(.semibold))
                        badge(strategy.kind.title)
                        if strategy.id == profile.defaultStrategy { badge(String(localized: "Default Strategy")) }
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Now")
                            .foregroundStyle(.secondary)
                        Text(reach?.node?.label ?? reach?.outcome?.title(in: profile) ?? "—")
                        if let node = reach?.node { ProxyDelayText(delay: node.delay(for: strategy.testURL)) }
                        if let via = reach?.via.first.flatMap(profile.strategy) {
                            Text("via \(via.name)").foregroundStyle(.tertiary)
                        }
                    }
                    Text(usage).foregroundStyle(.secondary).lineLimit(2)
                }
                .font(.callout)
                Spacer()
                if manager.testingStrategies.contains(strategy.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Test Delays") { coordinator.testDelays(of: strategy.id) }
                        .disabled(!manager.isRunning)
                }
                Button("Edit…") { openEditor(.strategy(ProxyStrategyDraft(strategy: strategy))) }
            }
        }
        .contextMenu {
            if strategy.id != profile.defaultStrategy {
                Button("Delete…", role: .destructive) { coordinator.deleteStrategy(strategy.id) }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Capsule().fill(Theme.Colors.controlSurface))
    }

    /// The routes, rules and strategies that send traffic here.
    private var usage: String {
        let users = ProxyStrategySummary.users(of: strategy.id, in: profile)
        guard !users.isEmpty else { return String(localized: "Nothing sends traffic here yet.") }
        return String(localized: "Used by \(users.formatted(.list(type: .and)))")
    }

    @ViewBuilder
    private func options(_ group: ProxySnapshot.Group) -> some View {
        let nodes = manager.snapshot?.nodes ?? [:]
        let members = group.options.filter { nodes[$0] == nil }
        let pool = group.options.compactMap { nodes[$0] }
        let picks = strategy.kind == .select
        if !members.isEmpty {
            ProxySectionHeader(title: String(localized: "Strategies"), caption: "\(members.count)")
            ProxyCardGrid {
                ForEach(members, id: \.self) { option in
                    memberCard(option, isCurrent: group.current == option, picks: picks)
                }
            }
        }
        if pool.isEmpty {
            ProxyNote(
                text: String(
                    localized: "No node falls within this strategy's range. Check the sources, or widen its regions."))
        } else if strategy.kind == .fallback {
            ProxySectionHeader(title: String(localized: "In Order"), caption: "\(pool.count)")
            ProxyCardGrid {
                ForEach(Array(pool.enumerated()), id: \.element.id) { index, node in
                    ProxyNodeCard(
                        node: node, detail: node.detail, delay: node.delay(for: strategy.testURL), tint: tint,
                        isCurrent: group.current == node.name, order: index + 1)
                }
            }
        } else {
            ProxyRegionSections(nodes: pool) { node in
                ProxyNodeCard(
                    node: node, detail: node.detail, delay: node.delay(for: strategy.testURL), tint: tint,
                    isCurrent: group.current == node.name,
                    pick: picks ? { coordinator.use(node.name, in: strategy.id) } : nil)
            }
        }
    }

    private var tint: Color { strategy.tint.color }

    private func memberCard(_ option: String, isCurrent: Bool, picks: Bool) -> some View {
        let member = profile.strategies.first { $0.name == option }
        let node = member.flatMap { manager.snapshot?.node(reachedBy: $0.id, in: profile) }
        return ProxyOptionCard(
            title: ProxyPaletteRows.optionTitle(option), detail: node?.label ?? "",
            delay: node.map { $0.delay(for: member?.testURL) }, tint: tint, isCurrent: isCurrent,
            leading: member.map { AnyView(ProxyTintDot(tint: $0.tint, size: Theme.Size.colorDot)) },
            pick: picks ? { coordinator.use(option, in: strategy.id) } : nil)
    }
}

/// Every node the enabled sources hold, by region, filtered to one source when asked.
private struct ProxyAllNodes: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    @State private var source: UUID?

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        ProxyCard {
            HStack(spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("All Nodes").font(.title3.weight(.semibold))
                    Text("Every node the sources bring. To use one, pick it in a strategy.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if manager.isTestingSources {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Test All") { core.proxyCoordinator.testAllNodes() }
                        .disabled(!manager.isRunning)
                }
                if profile.sources.count > 1 {
                    Picker(selection: $source) {
                        Text("All Sources").tag(UUID?.none)
                        ForEach(profile.sources.filter(\.isEnabled)) { source in
                            Text(source.name).tag(UUID?.some(source.id))
                        }
                    } label: {
                        Text("Source")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        if let snapshot = manager.snapshot {
            let nodes = snapshot.nodes.values
                .filter { source == nil || $0.source == source }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            ProxyRegionSections(nodes: nodes) { node in
                ProxyNodeCard(
                    node: node, detail: detail(of: node), delay: node.latest, tint: Theme.Colors.primaryAction,
                    isCurrent: false)
            }
        } else {
            ProxyNote(text: String(localized: "Connect to load the nodes of the enabled sources."))
        }
    }

    private func detail(of node: ProxySnapshot.Node) -> String {
        let source = profile.sources.first { $0.id == node.source }?.name
        return [node.detail, source].compactMap(\.self).joined(separator: " · ")
    }
}

/// Nodes under a header per region, in the region table's order, those naming none last.
struct ProxyRegionSections<Card: View>: View {
    let nodes: [ProxySnapshot.Node]
    @ViewBuilder let card: (ProxySnapshot.Node) -> Card

    var body: some View {
        let grouped = Dictionary(grouping: nodes, by: \.region)
        let regions: [ProxyRegion?] = ProxyRegion.allCases.map(Optional.some) + [nil]
        ForEach(regions.filter { grouped[$0] != nil }, id: \.self) { region in
            let members = grouped[region] ?? []
            ProxySectionHeader(title: region?.label ?? ProxyRegion.otherTitle, caption: "\(members.count)")
            ProxyCardGrid {
                ForEach(members) { card($0) }
            }
        }
    }
}

/// Cards in as many columns as fit.
struct ProxyCardGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: ProxyOptionCard.minimumWidth), spacing: Theme.Spacing.md, alignment: .top)
            ],
            alignment: .leading, spacing: Theme.Spacing.md
        ) {
            content
        }
    }
}

/// A node as a card: flag and name, its protocol, and how fast it answered.
struct ProxyNodeCard: View {
    @Environment(AppCore.self) private var core
    let node: ProxySnapshot.Node
    let detail: String
    let delay: ProxyDelay
    let tint: Color
    let isCurrent: Bool
    var order: Int?
    var pick: (() -> Void)?

    var body: some View {
        ProxyOptionCard(
            title: node.label, detail: detail, delay: delay, tint: tint, isCurrent: isCurrent, order: order,
            pick: pick
        )
        .contextMenu {
            Button("Test Delay") { core.proxyCoordinator.testNode(node.name) }
            Button("Copy Name") { core.proxyCoordinator.copyNodeName(node.name) }
        }
    }
}

/// The card both a node and a member strategy take; a pick makes it a button.
struct ProxyOptionCard: View {
    static let minimumWidth = 190.0

    let title: String
    let detail: String
    let delay: ProxyDelay?
    let tint: Color
    let isCurrent: Bool
    var order: Int?
    var leading: AnyView?
    var pick: (() -> Void)?

    var body: some View {
        if let pick {
            Button(action: pick) { card }
                .buttonStyle(.plain)
                .help(Text("Use \(title)"))
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(accessibilityDetail))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                if let order { Text(order, format: .number).font(.caption).foregroundStyle(.secondary) }
                leading
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if isCurrent {
                    SymbolImage(name: "checkmark.circle.fill", size: Theme.Size.settingsSidebarGlyph)
                        .foregroundStyle(tint)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let delay { ProxyDelayText(delay: delay) }
            }
            .font(.caption)
        }
        .padding(Theme.Spacing.lg)
        .background(shape.fill(isCurrent ? tint.opacity(0.14) : Theme.Colors.cardFill))
        .overlay(shape.strokeBorder(isCurrent ? tint.opacity(0.7) : Theme.Colors.cardStroke))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }

    private var accessibilityDetail: String {
        [detail, delay?.label].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension ProxySnapshot.Node {
    /// The protocol, and whether it carries UDP.
    var detail: String {
        supportsUDP ? "\(kind) · UDP" : kind
    }
}

import SwiftUI

/// One strategy at a time: where it exits now, the strategies it can pick, and its nodes by region.
struct ProxyNodesPane: View {
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    @Bindable var state: ProxyWindowState

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        ProxyPage {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ProxyStrategyTags(strategies: profile.strategies, selection: selection)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("By Region…") { openEditor(.regionStrategies) }
                } label: {
                    Label("New Strategy", systemImage: "plus")
                } primaryAction: {
                    openEditor(.strategy(ProxyStrategyDraft.new(in: profile, forRoute: nil)))
                }
                .fixedSize()
                Button("Node Pool…") { openEditor(.nodes(nil)) }
                    .help(Text("Every node the sources bring, whichever strategy uses it"))
            }
            if let strategy = profile.strategy(selected) {
                ProxyStrategyDetail(manager: manager, strategy: strategy, state: state)
            }
        }
    }

    private var selected: UUID {
        state.nodesStrategy.flatMap { profile.strategy($0)?.id } ?? profile.defaultStrategy
    }

    private var selection: Binding<UUID> {
        Binding(get: { selected }, set: { state.nodesStrategy = $0 })
    }
}

/// Every strategy as a tag, wrapping onto another row as they grow, so none hides in a menu.
private struct ProxyStrategyTags: View {
    let strategies: [ProxyStrategy]
    @Binding var selection: UUID

    var body: some View {
        ProxyWrapLayout {
            ForEach(strategies) { strategy in
                ProxyStrategyTag(strategy: strategy, isSelected: strategy.id == selection) {
                    selection = strategy.id
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Strategy"))
    }
}

private struct ProxyStrategyTag: View {
    let strategy: ProxyStrategy
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.sm) {
                ProxyTintDot(tint: strategy.tint, size: Theme.Size.colorDot)
                Text(strategy.name).lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: 28)
            .frame(maxWidth: 240)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(isSelected ? strategy.tint.color.opacity(0.7) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return strategy.tint.color.opacity(0.18) }
        return isHovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface
    }
}

/// One strategy: a summary of where it exits, then what it picks among.
private struct ProxyStrategyDetail: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    let strategy: ProxyStrategy
    @Bindable var state: ProxyWindowState

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var group: ProxySnapshot.Group? { manager.snapshot?.strategies[strategy.id] }
    private var picks: Bool { strategy.kind == .select }

    var body: some View {
        summary
        if let group {
            options(group)
        } else {
            ProxyNote(text: String(localized: "Connect to see the nodes this strategy can pick."))
        }
    }

    private var summary: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ProxyTintDot(tint: strategy.tint, size: Theme.Size.colorDot)
                    Text(strategy.name).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(facts).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: Theme.Spacing.md)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Test Delays") { coordinator.testDelays(of: strategy.id) }
                            .disabled(!manager.isRunning)
                    }
                    Button("Edit…") { openEditor(.strategy(ProxyStrategyDraft(strategy: strategy))) }
                }
                if manager.isRunning { exit }
                // A manual pick needs no telling; the others say why their nodes ignore a click.
                if strategy.kind != .select {
                    Text(strategy.kind.explanation).foregroundStyle(.secondary)
                }
                origin
                Text(usage).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
        }
        .contextMenu {
            if strategy.id != profile.defaultStrategy {
                Button("Delete…", role: .destructive) { coordinator.deleteStrategy(strategy.id) }
            }
        }
    }

    /// Its own test, or the one every source's nodes go through after a connect or a reload.
    private var isTesting: Bool {
        manager.testingStrategies.contains(strategy.id) || (manager.isTestingSources && strategy.pool != nil)
    }

    /// The sources the nodes come from, each a way to its card.
    @ViewBuilder private var origin: some View {
        let sources = strategy.pool.map { pool in
            profile.sources.filter { $0.isEnabled && (pool.sources?.contains($0.id) ?? true) }
        } ?? []
        if !sources.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Nodes from").foregroundStyle(.secondary)
                ForEach(sources) { source in
                    Button {
                        state.page = .sources
                    } label: {
                        ProxySourceTag(source: source)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show in Subscriptions"))
                }
            }
        }
    }

    private var facts: String {
        let kind = strategy.kind.title
        guard strategy.id == profile.defaultStrategy else { return kind }
        return kind + " · " + String(localized: "Default Strategy")
    }

    @ViewBuilder private var exit: some View {
        let reach = manager.snapshot?.reach(from: strategy.id, in: profile)
        HStack(spacing: Theme.Spacing.sm) {
            Text("Now").foregroundStyle(.secondary)
            if let node = reach?.node {
                ProxyNodeLabel(node: node)
                ProxyDelayText(delay: node.delay(for: strategy.testURL))
            } else {
                Text(reach?.outcome?.title(in: profile) ?? String(localized: "No node picked"))
            }
            if let via = reach?.via.first.flatMap(profile.strategy) {
                Text("via \(via.name)").foregroundStyle(.tertiary).lineLimit(1)
            }
        }
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
        let inUse = manager.snapshot?.node(reachedBy: strategy.id, in: profile)?.name
        let members = group.options.filter { nodes[$0] == nil }
        let all = group.options.compactMap { nodes[$0] }
        let sources = profile.sources.filter { source in all.contains { $0.source == source.id } }
        let shown = sources.contains { $0.id == state.nodesSource } ? state.nodesSource : nil
        let pool = all.filter { shown == nil || $0.source == shown }
        if !members.isEmpty {
            ProxySectionHeader(title: String(localized: "Strategies"))
            ProxyChipGrid {
                ForEach(members, id: \.self) { option in
                    memberChip(option, isCurrent: group.current == option)
                }
            }
        }
        if pool.isEmpty {
            ProxyNote(
                text: String(
                    localized: "No node falls within this strategy's range. Check the sources, or widen its regions."))
        } else if strategy.kind == .fallback {
            // Numbered among all of them, so a list narrowed to one source keeps the true order.
            let ordered = Array(all.enumerated()).filter { pool.contains($0.element) }
            ProxySectionHeader(title: String(localized: "In Order"), caption: "\(pool.count)") {
                sourceFilter(sources)
            }
            ProxyCard {
                ProxyChipGrid {
                    ForEach(ordered, id: \.element.id) { index, node in
                        nodeChip(node, isCurrent: group.current == node.name, isInUse: inUse == node.name, order: index + 1)
                    }
                }
            }
        } else {
            ProxyRegionList(
                groups: ProxyRegionGroup.groups(of: pool), inUse: inUse, testURL: strategy.testURL,
                expansion: $state.regionExpansion
            ) { node in
                nodeChip(node, isCurrent: group.current == node.name, isInUse: inUse == node.name, showsFlag: false)
            } accessory: {
                sourceFilter(sources)
            }
        }
    }

    /// Several sources feeding one strategy can be looked at one at a time.
    @ViewBuilder
    private func sourceFilter(_ sources: [ProxySource]) -> some View {
        if sources.count > 1 {
            Picker("Source", selection: $state.nodesSource) {
                Text("All Sources").tag(UUID?.none)
                Divider()
                ForEach(sources) { source in
                    Text(source.name).tag(UUID?.some(source.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
    }

    private var tint: Color { strategy.tint.color }

    private func memberChip(_ option: String, isCurrent: Bool) -> some View {
        let member = profile.strategies.first { $0.name == option }
        let node = member.flatMap { manager.snapshot?.node(reachedBy: $0.id, in: profile) }
        return ProxyChip(
            isCurrent: isCurrent, tint: tint, delay: node.map { $0.delay(for: member?.testURL) },
            pick: picks ? { coordinator.use(option, in: strategy.id) } : nil
        ) {
            if let member {
                ProxyTintDot(tint: member.tint, size: Theme.Size.colorDot).frame(width: Theme.Size.colorDot)
            }
            Text(ProxyPaletteRows.optionTitle(option)).lineLimit(1).layoutPriority(1)
            if let node {
                ProxyNodeLabel(node: node, showsNote: false).foregroundStyle(.secondary)
            }
        }
        .help(Text(node?.name ?? ProxyPaletteRows.optionTitle(option)))
    }

    private func nodeChip(
        _ node: ProxySnapshot.Node, isCurrent: Bool, isInUse: Bool, order: Int? = nil, showsFlag: Bool = true
    ) -> some View {
        ProxyChip(
            isCurrent: isCurrent, isInUse: isInUse, tint: tint, delay: node.delay(for: strategy.testURL),
            pick: picks ? { coordinator.use(node.name, in: strategy.id) } : nil
        ) {
            if let order {
                Text(order, format: .number).monospacedDigit().foregroundStyle(.tertiary)
            }
            ProxyNodeLabel(node: node, showsFlag: showsFlag)
        }
        .help(Text(node.tooltip(source: profile.sources.first { $0.id == node.source }?.origin)))
        .contextMenu {
            Button("Test Delay") { coordinator.testNode(node.name) }
            Button("Copy Name") { coordinator.copyNodeName(node.name) }
        }
    }
}

/// The nodes of one region, or of none; the order follows the region table, the unnamed last.
struct ProxyRegionGroup: Identifiable, Equatable {
    let region: ProxyRegion?
    let nodes: [ProxySnapshot.Node]

    /// Up to this many nodes read at a glance, so every region starts open.
    static let openCount = 24

    var id: String { region?.rawValue ?? "" }
    var title: String { region?.title ?? ProxyRegion.otherTitle }

    static func groups(of nodes: [ProxySnapshot.Node]) -> [ProxyRegionGroup] {
        let grouped = Dictionary(grouping: nodes, by: \.region)
        let regions: [ProxyRegion?] = ProxyRegion.allCases.map(Optional.some) + [nil]
        return regions.compactMap { region in
            grouped[region].map { ProxyRegionGroup(region: region, nodes: $0) }
        }
    }

    func fastest(for url: String?) -> Int? {
        nodes.compactMap {
            if case .milliseconds(let value) = $0.delay(for: url) { return value }
            return nil
        }.min()
    }
}

/// A row per region that opens onto its nodes; a short list opens whole, a long one at the pick.
struct ProxyRegionList<Chip: View, Accessory: View>: View {
    let groups: [ProxyRegionGroup]
    /// The node traffic goes out through, whether picked here or by a strategy picked here.
    let inUse: String?
    var testURL: String?
    @Binding var expansion: [String: Bool]
    @ViewBuilder let chip: (ProxySnapshot.Node) -> Chip
    @ViewBuilder var accessory: Accessory

    var body: some View {
        let count = groups.reduce(0) { $0 + $1.nodes.count }
        ProxySectionHeader(title: String(localized: "Nodes"), caption: "\(count)") {
            accessory
            if groups.count > 1 {
                let opensAll = groups.contains { !isExpanded($0) }
                Button(opensAll ? "Expand All" : "Collapse All") {
                    for group in groups { expansion[group.id] = opensAll }
                }
                .buttonStyle(.link)
            }
        }
        ProxyCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(groups) { group in
                    let isOpen = isExpanded(group)
                    ProxyRegionHeader(group: group, isOpen: isOpen, holdsInUse: holdsInUse(group), testURL: testURL) {
                        expansion[group.id] = !isOpen
                    }
                    if isOpen {
                        ProxyChipGrid {
                            ForEach(group.nodes) { chip($0) }
                        }
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    if group.id != groups.last?.id { Divider().padding(.leading, Theme.Spacing.xl) }
                }
            }
        }
    }

    private func holdsInUse(_ group: ProxyRegionGroup) -> Bool {
        group.nodes.contains { $0.name == inUse }
    }

    private func isExpanded(_ group: ProxyRegionGroup) -> Bool {
        expansion[group.id]
            ?? (holdsInUse(group) || groups.reduce(0) { $0 + $1.nodes.count } <= ProxyRegionGroup.openCount)
    }
}

/// A region's row: its flag and name, how many nodes it holds, and the fastest of them.
private struct ProxyRegionHeader: View {
    let group: ProxyRegionGroup
    let isOpen: Bool
    let holdsInUse: Bool
    let testURL: String?
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.md) {
                SymbolImage(name: "chevron.right", size: Theme.Size.settingsSidebarGlyph * 0.8)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: Theme.Size.settingsSidebarGlyph)
                if let flag = group.region?.flagEmoji {
                    ProxyFlag(emoji: flag)
                } else {
                    SymbolImage(name: "globe", size: Theme.Size.settingsSidebarGlyph).foregroundStyle(.secondary)
                }
                Text(group.title)
                Text(group.nodes.count, format: .number).foregroundStyle(.secondary)
                if holdsInUse {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: Theme.Size.colorDot * 0.75, height: Theme.Size.colorDot * 0.75)
                        .help(Text("The node in use is here"))
                        .accessibilityLabel(Text("The node in use is here"))
                }
                Spacer(minLength: Theme.Spacing.md)
                if let fastest = group.fastest(for: testURL) {
                    ProxyDelayText(delay: .milliseconds(fastest)).font(.callout)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(height: 38)
            .background(isHovered ? Theme.Colors.rowHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(group.title))
        .accessibilityValue(Text(isOpen ? "Expanded" : "Collapsed"))
    }
}

/// Chips in as many columns as fit.
struct ProxyChipGrid<Content: View>: View {
    var minimumWidth = 168.0
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: Theme.Spacing.sm, alignment: .top)],
            alignment: .leading, spacing: Theme.Spacing.sm
        ) {
            content
        }
    }
}

/// A node or a strategy to pick, in one line: what it is, a note in grey, and how fast it answered.
struct ProxyChip<Content: View>: View {
    let isCurrent: Bool
    /// Carrying the traffic without being this strategy's own pick, as through another strategy.
    var isInUse = false
    let tint: Color
    let delay: ProxyDelay?
    /// A word where the delay goes, for a chip that has no delay to show.
    var note: Text?
    var pick: (() -> Void)?
    @ViewBuilder let label: Content
    @State private var isHovered = false

    var body: some View {
        if let pick {
            Button(action: pick) { chip }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            label
            Spacer(minLength: Theme.Spacing.xs)
            if let delay {
                ProxyDelayText(delay: delay, marksUntested: true).font(.caption)
            } else if let note {
                note.font(.caption).foregroundStyle(.tertiary).fixedSize()
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 30)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(isCurrent || isInUse ? tint.opacity(0.7) : .clear))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var fill: Color {
        if isCurrent { return tint.opacity(0.16) }
        return isHovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
    }
}

extension ProxySnapshot.Node {
    /// The whole name, the protocol, and where it came from.
    func tooltip(source: String?) -> String {
        ([name, detail] + [source].compactMap(\.self)).joined(separator: "\n")
    }

    /// The protocol, and whether it carries UDP.
    var detail: String {
        supportsUDP ? "\(kind) · UDP" : kind
    }
}

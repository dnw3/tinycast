import SwiftUI

/// One strategy's options as the core offers them: its member strategies, then nodes by region.
struct ProxyNodesScreen: PaletteScreen {
    private enum Item {
        case connect
        case option(String)
    }

    let manager: ProxyManager
    let coordinator: ProxyCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let openActions: () -> Void
    let rows: [ProxyPaletteRow]
    private let items: [Item]
    private let strategy: ProxyStrategy?

    init(
        manager: ProxyManager, coordinator: ProxyCoordinator, vm: PaletteState, metrics: InterfaceMetrics,
        openActions: @escaping () -> Void
    ) {
        self.manager = manager
        self.coordinator = coordinator
        self.vm = vm
        self.metrics = metrics
        self.openActions = openActions
        let profile = manager.store.profile
        let strategy = profile.strategy(coordinator.session.strategyID ?? profile.defaultStrategy)
        self.strategy = strategy
        guard let strategy, let snapshot = manager.snapshot, let group = snapshot.strategies[strategy.id]
        else {
            let connect = manager.isRunning ? [] : [ProxyPaletteRows.connectRow()]
            items = connect.map { _ in .connect }
            rows = connect
            return
        }
        let query = FuzzyMatch.Query(vm.query)
        let sources = Dictionary(uniqueKeysWithValues: profile.sources.map { ($0.id, $0.name) })
        let namesSources = profile.sources.filter(\.isEnabled).count > 1
        var members: [(Item, ProxyPaletteRow)] = []
        var byRegion: [ProxyRegion?: [(Item, ProxyPaletteRow)]] = [:]
        for option in group.options {
            if let node = snapshot.nodes[option] {
                let source = namesSources ? node.source.flatMap { sources[$0] } : nil
                guard ProxyPaletteRows.matches(query, node.name, node.region?.title, source) else { continue }
                let delay = node.delay(for: strategy.testURL)
                let name = ProxyNodeName(node.name)
                let subtitle = [name.note, source].compactMap(\.self).joined(separator: " · ")
                byRegion[node.region, default: []].append(
                    (
                        .option(option),
                        ProxyPaletteRow(
                            id: option, leading: .flag(node.flagEmoji), title: name.title,
                            subtitle: subtitle.isEmpty ? nil : subtitle,
                            trailing: delay.label, trailingTone: ProxyPaletteRow.Tone(delay),
                            isCurrent: group.current == option)
                    ))
            } else {
                let title = ProxyPaletteRows.optionTitle(option)
                guard ProxyPaletteRows.matches(query, title) else { continue }
                let member = profile.strategies.first { $0.name == option }
                let reached = member.flatMap { snapshot.node(reachedBy: $0.id, in: profile) }
                let delay = reached.map { $0.delay(for: member?.testURL) }
                let leading: ProxyPaletteRow.Leading =
                    member.map { .tint($0.tint) } ?? .symbol(option == "DIRECT" ? "arrow.right" : "nosign")
                members.append(
                    (
                        .option(option),
                        ProxyPaletteRow(
                            id: option, section: String(localized: "Options"), leading: leading, title: title,
                            subtitle: reached?.label, trailing: delay?.label,
                            trailingTone: delay.map(ProxyPaletteRow.Tone.init) ?? .secondary,
                            isCurrent: group.current == option)
                    ))
            }
        }
        var pairs = members
        let regions: [ProxyRegion?] = ProxyRegion.allCases.map(Optional.some) + [nil]
        for region in regions {
            guard var nodes = byRegion[region] else { continue }
            let title = region?.label ?? ProxyRegion.otherTitle
            let section = "\(title) · \(nodes.count)"
            for index in nodes.indices { nodes[index].1.section = section }
            pairs += nodes
        }
        items = pairs.map(\.0)
        rows = pairs.map(\.1)
    }

    private var profile: ProxyProfile { manager.store.profile }

    private func option(at selection: Int) -> String? {
        guard items.indices.contains(selection), case .option(let option) = items[selection] else {
            return nil
        }
        return option
    }

    var landingSelection: Int {
        guard let strategy, let current = manager.snapshot?.strategies[strategy.id]?.current else { return 0 }
        return items.firstIndex {
            if case .option(let option) = $0 { return option == current }
            return false
        } ?? 0
    }

    /// Only a manual strategy takes a pick; the others choose by delay, so ↵ tests instead.
    private var isManual: Bool { strategy?.kind == .select }

    var primaryActionTitle: String {
        guard let option = option(at: vm.selection) else { return String(localized: "Connect Proxy") }
        return isManual ? useTitle(for: option) : String(localized: "Test Delay")
    }

    /// A member strategy, Direct or Reject is an option to use, not a node.
    private func useTitle(for option: String) -> String {
        manager.snapshot?.nodes[option] != nil
            ? String(localized: "Use This Node") : String(localized: "Use This Option")
    }

    func activate(at selection: Int) {
        guard let option = option(at: selection) else {
            if items.indices.contains(selection) { coordinator.connect() }
            return
        }
        guard let strategy else { return }
        if isManual {
            coordinator.use(option, in: strategy.id)
        } else {
            coordinator.testNode(option)
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    func navigateHorizontally(_ delta: Int, at selection: Int) -> Bool {
        guard delta < 0, vm.canGoBack else { return false }
        coordinator.back()
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .copyName:
            guard let option = option(at: selection) else { return false }
            coordinator.copyNodeName(option)
        case .edit, .settings:
            guard let strategy else { return false }
            coordinator.showWindow(edit: .editStrategy(strategy.id))
        default:
            return false
        }
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let strategy else { return nil }
        var items: [PopoverMenuItem] = []
        let option = option(at: selection)
        if let option {
            if isManual {
                items.append(
                    PopoverMenuItem(title: useTitle(for: option), systemImage: "checkmark", shortcut: "↵") {
                        coordinator.use(option, in: strategy.id)
                    })
            }
            if manager.snapshot?.nodes[option] != nil {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Test Delay"), systemImage: "speedometer",
                        isEnabled: manager.isRunning, shortcut: isManual ? nil : "↵"
                    ) {
                        coordinator.testNode(option)
                    })
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Copy Name"), systemImage: "doc.on.doc", shortcut: "⌥⌘C"
                    ) {
                        coordinator.copyNodeName(option)
                    })
            }
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Test All in “\(strategy.name)”"), systemImage: "speedometer",
                isEnabled: manager.isRunning, startsSection: !items.isEmpty
            ) {
                coordinator.testDelays(of: strategy.id)
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Edit “\(strategy.name)”…"), systemImage: "pencil", shortcut: "⌘E"
            ) {
                coordinator.showWindow(edit: .editStrategy(strategy.id))
            })
        let others = profile.strategies.filter { $0.id != strategy.id }
        for (index, other) in others.enumerated() {
            items.append(
                PopoverMenuItem(
                    title: other.name, icon: .symbol("circle.fill"),
                    sectionTitle: index == 0 ? String(localized: "Switch Strategy") : nil,
                    startsSection: index == 0
                ) {
                    coordinator.switchNodes(to: other.id)
                })
        }
        items.append(ProxyPaletteActions.connectionItem(coordinator: coordinator, manager: manager))
        return PopoverMenuContent(
            header: option.map(ProxyPaletteRows.optionTitle) ?? strategy.name, items: items)
    }

    func headerAccessory(at selection: Int, focus: FocusState<String?>.Binding) -> PaletteHeaderAccessory? {
        guard let strategy else { return nil }
        return ProxyContextChip.accessory(
            title: strategy.name, leading: .tint(strategy.tint), metrics: metrics)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard !rows.isEmpty else {
            let text =
                manager.snapshot == nil
                ? String(localized: "Loading nodes…") : String(localized: "No matching nodes")
            return AnyView(EmptyResults(text: text))
        }
        let selected = rows.indices.contains(selection) ? rows[selection].id : nil
        return AnyView(
            HStack(spacing: 0) {
                ProxyPaletteList(
                    rows: rows, selectedID: selected, scroll: scroll,
                    onSelect: { vm.selection = $0 },
                    onActivate: { index in
                        vm.selection = index
                        activate(at: index)
                    },
                    onActions: { _ in openActions() }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                ProxyNodeDetail(option: option(at: selection), strategy: strategy, manager: manager)
            })
    }
}

/// The highlighted option at length: its delay, its source, and which routes it would carry.
private struct ProxyNodeDetail: View {
    @Environment(\.metrics) private var metrics
    let option: String?
    let strategy: ProxyStrategy?
    let manager: ProxyManager

    private struct Fact: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        if let option, let strategy {
            VStack(alignment: .leading, spacing: metrics.spacing.xl) {
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text(ProxyPaletteRows.optionTitle(option, in: manager.snapshot))
                        .font(metrics.typography.panelTitle)
                        .lineLimit(2)
                    if let subtitle = subtitle(of: option) {
                        Text(subtitle)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.secondary)
                    }
                }
                if let delay = delay(of: option, in: strategy) {
                    Text(delay.label ?? String(localized: "Not tested yet"))
                        .font(metrics.typography.readout)
                        .foregroundStyle(ProxyPaletteRow.Tone(delay).color)
                }
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text("Information")
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    VStack(spacing: 0) {
                        let facts = facts(of: option, in: strategy)
                        ForEach(facts) { fact in
                            if fact.id != facts.first?.id { Divider() }
                            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                                Text(fact.label).foregroundStyle(Theme.Colors.textSecondary)
                                Spacer(minLength: metrics.spacing.lg)
                                Text(fact.value)
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(3)
                            }
                            .font(metrics.typography.keyCap)
                            .padding(.vertical, metrics.spacing.xs)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(metrics.spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    private func subtitle(of option: String) -> String? {
        if let node = manager.snapshot?.nodes[option] {
            return node.region?.title ?? ProxyRegion.otherTitle
        }
        if let member = profile.strategies.first(where: { $0.name == option }) {
            return String(localized: "Strategy · \(member.kind.title)")
        }
        return option == "DIRECT" ? ProxyTarget.directSubtitle : ProxyTarget.rejectSubtitle
    }

    private func delay(of option: String, in strategy: ProxyStrategy) -> ProxyDelay? {
        if let node = manager.snapshot?.nodes[option] { return node.delay(for: strategy.testURL) }
        guard let member = profile.strategies.first(where: { $0.name == option }),
            let node = manager.snapshot?.node(reachedBy: member.id, in: profile)
        else { return nil }
        return node.delay(for: member.testURL)
    }

    private func facts(of option: String, in strategy: ProxyStrategy) -> [Fact] {
        var facts: [Fact] = []
        if let node = manager.snapshot?.nodes[option] {
            if let source = node.source.flatMap({ id in profile.sources.first { $0.id == id } }) {
                facts.append(Fact(label: String(localized: "Source"), value: source.name))
            }
            let udp = node.supportsUDP ? String(localized: "UDP supported") : String(localized: "No UDP")
            facts.append(Fact(label: String(localized: "Protocol"), value: "\(node.kind) · \(udp)"))
        } else if let member = profile.strategies.first(where: { $0.name == option }),
            let reached = manager.snapshot?.node(reachedBy: member.id, in: profile)
        {
            facts.append(Fact(label: String(localized: "Now"), value: reached.name))
        }
        let users = ProxyStrategySummary.users(of: strategy.id, in: profile)
        facts.append(
            Fact(
                label: String(localized: "Picking It Affects"),
                value: users.isEmpty
                    ? String(localized: "Nothing routes through “\(strategy.name)”")
                    : "\(strategy.name): \(users.formatted(.list(type: .and)))"))
        return facts
    }
}

import SwiftUI

/// Where a new rule's traffic goes: a strategy, Direct or Reject, picked after its match.
struct ProxyStrategiesScreen: PaletteScreen {
    private enum Item {
        case target(ProxyTarget)
    }

    let manager: ProxyManager
    let coordinator: ProxyCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let openActions: () -> Void
    let rows: [ProxyPaletteRow]
    private let items: [Item]
    private let rule: ProxyPaletteSession.RuleDraft?

    init(
        manager: ProxyManager, coordinator: ProxyCoordinator, vm: PaletteState, metrics: InterfaceMetrics,
        openActions: @escaping () -> Void
    ) {
        self.manager = manager
        self.coordinator = coordinator
        self.vm = vm
        self.metrics = metrics
        self.openActions = openActions
        let rule = coordinator.session.rule
        self.rule = rule
        let profile = manager.store.profile
        let snapshot = manager.snapshot
        let query = FuzzyMatch.Query(vm.query)
        let current = rule.flatMap { Self.target(of: $0, in: profile) }
        var pairs: [(Item, ProxyPaletteRow)] = []
        let strategies = String(localized: "Strategies")
        for strategy in profile.strategies where ProxyPaletteRows.matches(query, strategy.name) {
            let target = ProxyTarget.strategy(strategy.id)
            var subtitle = strategy.kind.title
            var trailing: String?
            var tone = ProxyPaletteRow.Tone.secondary
            if let node = snapshot?.node(reachedBy: strategy.id, in: profile) {
                let delay = node.delay(for: strategy.testURL)
                subtitle += " · \(node.label)"
                trailing = delay.label
                tone = ProxyPaletteRow.Tone(delay)
            }
            pairs.append(
                (
                    .target(target),
                    ProxyPaletteRow(
                        id: strategy.id.uuidString, section: strategies, leading: .tint(strategy.tint),
                        title: strategy.name, subtitle: subtitle, trailing: trailing, trailingTone: tone,
                        isCurrent: current == target)
                ))
        }
        let builtIn = String(localized: "Built-in")
        let options: [(ProxyTarget, String)] = [
            (.direct, ProxyTarget.directSubtitle), (.reject, ProxyTarget.rejectSubtitle)
        ]
        for (target, subtitle) in options where ProxyPaletteRows.matches(query, target.title(in: profile)) {
            pairs.append(
                (
                    .target(target),
                    ProxyPaletteRow(
                        id: target.title(in: profile), section: builtIn, leading: .target(target, in: profile),
                        title: target.title(in: profile), subtitle: subtitle, isCurrent: current == target)
                ))
        }
        items = pairs.map(\.0)
        rows = pairs.map(\.1)
    }

    /// What an existing rule for the same match uses now, so the screen opens on it.
    private static func target(of rule: ProxyPaletteSession.RuleDraft, in profile: ProxyProfile) -> ProxyTarget? {
        profile.rules.first { $0.kind == rule.kind && $0.value == rule.value }?.target
    }

    private var profile: ProxyProfile { manager.store.profile }

    private func target(at selection: Int) -> ProxyTarget? {
        guard items.indices.contains(selection), case .target(let target) = items[selection] else { return nil }
        return target
    }

    var landingSelection: Int {
        guard let rule, let current = Self.target(of: rule, in: profile) else { return 0 }
        return items.firstIndex {
            if case .target(let target) = $0 { return target == current }
            return false
        } ?? 0
    }

    var primaryActionTitle: String { String(localized: "Use This Strategy") }

    func activate(at selection: Int) {
        guard let rule, let target = target(at: selection) else { return }
        coordinator.addRule(rule.kind, rule.value, to: target)
    }

    func secondary(at selection: Int) -> Bool { false }

    func navigateHorizontally(_ delta: Int, at selection: Int) -> Bool {
        guard delta < 0 else { return false }
        coordinator.back()
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .edit:
            guard let id = target(at: selection)?.strategyID else { return false }
            coordinator.showWindow(edit: .editStrategy(id))
        case .newItem:
            coordinator.showWindow(edit: .newStrategy(route: nil))
        case .settings:
            coordinator.showWindow(page: .nodes)
        default:
            return false
        }
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        let target = target(at: selection)
        if target != nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Use This Strategy"), systemImage: "checkmark", shortcut: "↵"
                ) {
                    activate(at: selection)
                })
        }
        if let id = target?.strategyID {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Edit Strategy…"), systemImage: "pencil", shortcut: "⌘E"
                ) {
                    coordinator.showWindow(edit: .editStrategy(id))
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "New Strategy…"), systemImage: "plus", startsSection: !items.isEmpty,
                shortcut: "⌘N"
            ) {
                coordinator.showWindow(edit: .newStrategy(route: nil))
            })
        items.append(ProxyPaletteActions.connectionItem(coordinator: coordinator, manager: manager))
        return PopoverMenuContent(header: target?.title(in: profile), items: items)
    }

    func headerAccessory(at selection: Int, focus: FocusState<String?>.Binding) -> PaletteHeaderAccessory? {
        guard let rule else { return nil }
        return ProxyContextChip.accessory(title: rule.value, leading: .symbol("text.badge.plus"), metrics: metrics)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard !rows.isEmpty else {
            return AnyView(EmptyResults(text: String(localized: "No matching strategies")))
        }
        let selected = rows.indices.contains(selection) ? rows[selection].id : nil
        return AnyView(
            ProxyPaletteList(
                rows: rows, selectedID: selected, scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { index in
                    vm.selection = index
                    activate(at: index)
                },
                onActions: { _ in openActions() }))
    }
}

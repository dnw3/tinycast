import SwiftUI

/// A new rule: the field holds a site, an address or an app, and each row is one way to match it.
struct ProxyRuleScreen: PaletteScreen {
    let manager: ProxyManager
    let coordinator: ProxyCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let openActions: () -> Void
    let rows: [ProxyPaletteRow]
    private let candidates: [(kind: ProxyUserRule.Kind, value: String)]

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
        candidates = ProxyUserRule.candidates(for: vm.query)
        let section = String(localized: "Match")
        rows = candidates.map { kind, value in
            let existing = profile.rules.first { $0.kind == kind && $0.value == value }
            return ProxyPaletteRow(
                id: kind.keyword + "," + value, section: section, leading: .symbol(kind.symbol),
                title: kind.description(of: value), subtitle: kind.title,
                trailing: existing.map { String(localized: "Now \($0.target.title(in: profile))") })
        }
    }

    private func candidate(at selection: Int) -> (kind: ProxyUserRule.Kind, value: String)? {
        candidates.indices.contains(selection) ? candidates[selection] : nil
    }

    var primaryActionTitle: String { String(localized: "Choose Strategy") }

    func activate(at selection: Int) {
        guard let candidate = candidate(at: selection) else { return }
        coordinator.pickStrategy(forRule: candidate.kind, value: candidate.value)
    }

    func secondary(at selection: Int) -> Bool { false }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .settings || shortcut == .edit else { return false }
        coordinator.showWindow(edit: .editRules)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        if let candidate = candidate(at: selection) {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Choose Strategy…"), systemImage: "arrow.right", shortcut: "↵"
                ) {
                    coordinator.pickStrategy(forRule: candidate.kind, value: candidate.value)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Edit My Rules…"), systemImage: "list.bullet",
                startsSection: !items.isEmpty,
                shortcut: "⌘E"
            ) {
                coordinator.showWindow(edit: .editRules)
            })
        return PopoverMenuContent(header: candidate(at: selection)?.value, items: items)
    }

    func headerAccessory(at selection: Int, focus: FocusState<String?>.Binding) -> PaletteHeaderAccessory? {
        guard let source = coordinator.session.ruleSource, !vm.query.isEmpty else { return nil }
        return ProxyContextChip.accessory(
            title: String(localized: "From \(source)"), leading: .symbol("globe"), metrics: metrics)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard !rows.isEmpty else {
            return AnyView(
                EmptyResults(
                    text: vm.query.isEmpty
                        ? String(localized: "Type a website, an address or an app")
                        : String(localized: "Not something a rule can match"),
                    detail: String(localized: "A rule sends it to a strategy ahead of every route."),
                    systemImage: "text.badge.plus"))
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

extension ProxyUserRule.Kind {
    var symbol: String {
        switch self {
        case .domainSuffix: "globe"
        case .domain: "link"
        case .domainKeyword: "text.magnifyingglass"
        case .ipCIDR: "number"
        case .processName: "app"
        }
    }

    /// What a rule of this kind with this value would catch, in words.
    func description(of value: String) -> String {
        switch self {
        case .domainSuffix: String(localized: "\(value) and its subdomains")
        case .domain: String(localized: "\(value) only")
        case .domainKeyword: String(localized: "Domains containing “\(value)”")
        case .ipCIDR: String(localized: "Addresses in \(value)")
        case .processName: String(localized: "Connections from the app “\(value)”")
        }
    }
}

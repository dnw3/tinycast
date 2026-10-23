import SwiftUI

/// Where each kind of traffic goes: a live test, the user's rules, the routes in order, the rest.
struct ProxyRoutesPane: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        ProxyPage {
            if manager.mode != .rule {
                ProxyNote(text: modeNote) {
                    Button("Use Rule Mode") { coordinator.setMode(.rule) }
                }
            }
            ProxyProbeCard(manager: manager)
            rules
            routes
            footer
        }
    }

    private var modeNote: String {
        manager.mode == .global
            ? String(localized: "Global mode sends everything through the default strategy, so these rules wait.")
            : String(localized: "Direct mode sends everything direct, so these rules wait.")
    }

    // MARK: - My rules

    @ViewBuilder private var rules: some View {
        let enabled = profile.rules.filter(\.isEnabled).count
        ProxySectionHeader(
            title: String(localized: "My Rules"),
            caption: String(localized: "\(enabled) rules · matched before every route")
        ) {
            Button("Edit…") { openEditor(.rules) }
        }
        if profile.rules.isEmpty {
            ProxyNote(text: String(localized: "Send one site, address or app somewhere else, ahead of every route.")) {
                Button("Add Rule…") { openEditor(.rules) }
            }
        } else {
            ProxyRowList(items: profile.rules) { rule in
                ProxyRuleRow(manager: manager, rule: rule)
            }
        }
    }

    // MARK: - Routes

    @ViewBuilder private var routes: some View {
        ProxySectionHeader(
            title: String(localized: "Routes"),
            caption: String(localized: "Top to bottom; the first match wins. Drag to reorder.")
        ) {
            Button("Add Route…") { openEditor(.addRoute) }
        }
        ProxyCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(profile.routes) { route in
                    ProxyRouteRow(manager: manager, route: route)
                    Divider().padding(.leading, Theme.Spacing.xxxl)
                }
                ProxyFinalRouteRow(manager: manager)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(ruleSetStatus).foregroundStyle(.secondary)
            // A disabled link still reads as a link, so one that cannot act is left out.
            if manager.isUpdatingRuleSets {
                ProgressView().controlSize(.small)
            } else if manager.isRunning {
                Button("Update Now") { coordinator.updateRuleSets() }
                    .buttonStyle(.link)
            }
            Spacer()
            if !profile.followsRecommendedRoutes {
                Button("Restore Recommended Routing…") { coordinator.restoreRecommendedRoutes() }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
    }

    private var ruleSetStatus: String {
        let names = Set(profile.routes.filter(\.isEnabled).flatMap(\.ruleSets).map(\.name))
        guard let loaded = manager.snapshot?.ruleSets else {
            return String(localized: "\(names.count) rule sets, downloaded once connected")
        }
        let ready = names.filter { (loaded[$0]?.rules ?? 0) > 0 }.count
        let updated = names.compactMap { loaded[$0]?.updatedAt }.max()
        let count = String(localized: "\(ready) of \(names.count) rule sets loaded")
        guard let updated else { return count }
        return count + " · " + String(localized: "Updated \(updated.formatted(.relative(presentation: .named)))")
    }
}

/// A card of rows split by hairlines.
private struct ProxyRowList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ProxyCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 { Divider().padding(.leading, Theme.Spacing.xxxl) }
                }
            }
        }
    }
}

/// One of the user's rules: what it matches, where it goes, and whether it is on.
private struct ProxyRuleRow: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let rule: ProxyUserRule

    var body: some View {
        let profile = manager.store.profile
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: rule.kind.symbol, size: Theme.Size.settingsSidebarGlyph)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(rule.value).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                Text(rule.kind.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ProxyTargetMenu(
                target: rule.target, profile: profile, snapshot: manager.snapshot,
                choose: { target in update { $0.target = target } })
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: { value in update { $0.isEnabled = value } })) {
                Text("Use \(rule.value)")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .proxyDimmed(!rule.isEnabled)
    }

    private func update(_ change: @escaping (inout ProxyUserRule) -> Void) {
        core.proxyCoordinator.update { profile in
            guard let index = profile.rules.firstIndex(where: { $0.id == rule.id }) else { return }
            change(&profile.rules[index])
        }
    }
}

/// One route: dragged to reorder, sent to a target, switched off, or removed from its menu.
private struct ProxyRouteRow: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    let route: ProxyRoute
    @State private var isTargeted = false

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        let profile = manager.store.profile
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "line.3.horizontal", size: Theme.Size.settingsSidebarGlyph)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            SymbolImage(name: route.symbol, size: Theme.Size.settingsSidebarGlyph)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(route.title).lineLimit(1)
                Text(route.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            ProxyTargetMenu(
                target: route.target, profile: profile, snapshot: manager.snapshot,
                choose: { coordinator.route(route.id, to: $0) },
                newStrategy: { openEditor(.strategy(ProxyStrategyDraft.new(in: profile, forRoute: route.id))) })
            Toggle(isOn: Binding(get: { route.isEnabled }, set: { _ in coordinator.toggleRoute(route.id) })) {
                Text("Use \(route.title)")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .proxyDimmed(!route.isEnabled)
        .background(alignment: .top) {
            if isTargeted { Rectangle().fill(Theme.Colors.dropTarget).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .draggable(route.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            coordinator.moveRoute(id, before: route.id)
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button("Move Up") { coordinator.moveRoute(route.id, by: -1) }
                .disabled(profile.routes.first?.id == route.id)
            Button("Move Down") { coordinator.moveRoute(route.id, by: 1) }
                .disabled(profile.routes.last?.id == route.id)
            if case .custom(_, let ruleSets) = route.kind, let linked = ruleSets.first(where: \.isLinked),
                case .url(let link) = linked.location
            {
                Divider()
                Button("Edit Rule Set…") { openEditor(.linkRoute(id: route.id, link: link)) }
            }
            Divider()
            Button("Remove", role: .destructive) { coordinator.removeRoute(route.id) }
        }
    }
}

/// The traffic nothing above claims; always last, and always on.
private struct ProxyFinalRouteRow: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager

    var body: some View {
        let profile = manager.store.profile
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "line.3.horizontal", size: Theme.Size.settingsSidebarGlyph).hidden()
            SymbolImage(name: "ellipsis", size: Theme.Size.settingsSidebarGlyph)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(ProxyRoute.finalTitle)
                Text(ProxyRoute.finalSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ProxyTargetMenu(
                target: profile.finalTarget, profile: profile, snapshot: manager.snapshot,
                choose: { core.proxyCoordinator.route(ProxyRoute.finalID, to: $0) },
                newStrategy: {
                    openEditor(.strategy(ProxyStrategyDraft.new(in: profile, forRoute: ProxyRoute.finalID)))
                })
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            core.proxyCoordinator.moveRoute(id, before: nil)
            return true
        }
    }
}

/// Types a site and asks the running core which rule it matches and where it exits.
private struct ProxyProbeCard: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    @State private var input = ""
    @State private var result: Result?
    @State private var isRunning = false

    private enum Result {
        case outcome(ProxyProbe)
        case failure(String)
    }

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    SymbolImage(name: "magnifyingglass", size: Theme.Size.settingsSidebarGlyph).foregroundStyle(.secondary)
                    TextField(
                        "Website or Address", text: $input, prompt: Text(ProxyPrompt.example("chat.openai.com"))
                    )
                    .textFieldStyle(.plain)
                    .onSubmit(run)
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Test", action: run)
                            .disabled(!manager.isRunning || ProxyProbe.Destination(input) == nil)
                    }
                }
                Group {
                    switch result {
                    case .outcome(let probe):
                        ProxyProbeResult(probe: probe, profile: profile, mode: manager.mode, snapshot: manager.snapshot)
                    case .failure(let message): Text(message).foregroundStyle(.secondary)
                    case nil:
                        Text(
                            manager.isRunning
                                ? String(localized: "See which rule a site matches and where it exits, as the core decides.")
                                : String(localized: "Connect to test where a site goes.")
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func run() {
        guard let destination = ProxyProbe.Destination(input), !isRunning else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            switch await core.proxyCoordinator.probe(destination) {
            case .success(let outcome): result = .outcome(ProxyProbe(destination: destination, outcome: outcome))
            case .failure(.unreachable): result = .failure(String(localized: "The core could not be reached."))
            case .failure(.noRecord):
                result = .failure(String(localized: "The core reported nothing for this site in time."))
            }
        }
    }
}

/// What a test found: the rule or route that matched, the strategy, and the exit.
private struct ProxyProbeResult: View {
    let probe: ProxyProbe
    let profile: ProxyProfile
    let mode: ProxyMode
    let snapshot: ProxySnapshot?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            switch probe.outcome {
            case .matched(let rule, let payload, let exit):
                Text("Matched").foregroundStyle(.secondary)
                Text(matchTitle(rule: rule, payload: payload)).fontWeight(.semibold)
                arrow
                if let target { ProxyTargetDot(target: target, profile: profile) }
                Text(target?.title(in: profile) ?? ProxyPaletteRows.optionTitle(exit, in: snapshot))
                if target?.strategyID != nil {
                    arrow
                    Text(ProxyPaletteRows.optionTitle(exit, in: snapshot))
                }
            case .mode(let exit):
                Text(mode == .global ? String(localized: "Global mode") : String(localized: "Direct mode"))
                    .fontWeight(.semibold)
                arrow
                Text(ProxyPaletteRows.optionTitle(exit, in: snapshot))
            case .failed(let rule, let payload, let reason):
                Text("Matched").foregroundStyle(.secondary)
                Text(matchTitle(rule: rule, payload: payload)).fontWeight(.semibold)
                Text("but could not connect: \(reason)").foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .lineLimit(1)
    }

    private var arrow: some View {
        SymbolImage(name: "arrow.right", size: Theme.Size.settingsSidebarGlyph)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var match: ProxyActivity.Match {
        switch probe.outcome {
        case .matched(let rule, let payload, _), .failed(let rule, let payload, _):
            ProxyActivity.matching(rule: rule, payload: payload, in: profile)
        case .mode: .mode
        }
    }

    private var target: ProxyTarget? {
        switch match {
        case .rule(let id): profile.rules.first { $0.id == id }?.target
        case .route(let id) where id == ProxyRoute.finalID: profile.finalTarget
        case .route(let id): profile.routes.first { $0.id == id }?.target
        case .mode, .core, .unknown: nil
        }
    }

    private func matchTitle(rule: String, payload: String) -> String {
        switch match {
        case .rule(let id): profile.rules.first { $0.id == id }.map { $0.kind.description(of: $0.value) } ?? payload
        case .route(let id) where id == ProxyRoute.finalID: ProxyRoute.finalTitle
        case .route(let id): profile.routes.first { $0.id == id }?.title ?? id
        case .mode, .core, .unknown: payload.isEmpty ? rule : "\(rule) \(payload)"
        }
    }
}

import SwiftUI

/// A strategy being added or changed, and the route waiting to use it when it was made for one.
struct ProxyStrategyDraft {
    var strategy: ProxyStrategy
    var isNew = false
    var route: String?

    init(strategy: ProxyStrategy) {
        self.strategy = strategy
    }

    static func new(in profile: ProxyProfile, forRoute route: String?) -> ProxyStrategyDraft {
        let used = Set(profile.strategies.map(\.tint))
        let tint = ProxyStrategy.Tint.allCases.first { !used.contains($0) } ?? .blue
        let base = String(localized: "New Strategy")
        let names = Set(profile.strategies.map { $0.name.lowercased() })
        let name =
            ([base] + (2...99).map { "\(base) \($0)" }).first { !names.contains($0.lowercased()) } ?? base
        var draft = ProxyStrategyDraft(
            strategy: ProxyStrategy(id: UUID(), name: name, kind: .urlTest, tint: tint))
        draft.isNew = true
        draft.route = route
        return draft
    }
}

/// Names a strategy, picks how it chooses, and says which nodes it chooses from.
struct ProxyStrategyEditor: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    private let isNew: Bool
    private let route: String?
    @State private var strategy: ProxyStrategy
    @State private var error: String?

    init(draft: ProxyStrategyDraft, manager: ProxyManager, close: @escaping () -> Void) {
        self.manager = manager
        self.close = close
        isNew = draft.isNew
        route = draft.route
        _strategy = State(initialValue: draft.strategy)
    }

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: isNew ? "New Strategy" : "Edit Strategy",
                subtitle: subtitle
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                identity
                options
                nodes
                if strategy.kind != .select { testing }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                if !isNew, strategy.id != profile.defaultStrategy {
                    Button("Delete…") {
                        close()
                        coordinator.deleteStrategy(strategy.id)
                    }
                    .buttonStyle(.modalAction(.destructive))
                }
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 620)
        .settingsEditorPanelSurface()
    }

    private var subtitle: LocalizedStringResource {
        let users = ProxyStrategySummary.users(of: strategy.id, in: profile)
        return users.isEmpty
            ? "\(strategy.kind.explanation)" : "Used by \(users.formatted(.list(type: .and)))"
    }

    // MARK: - Sections

    private var identity: some View {
        Section {
            SettingsEditorField("Name") {
                TextField("Name", text: $strategy.name).settingsEditorTextField()
            }
            SettingsEditorField("Color") {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(ProxyStrategy.Tint.allCases, id: \.self) { tint in
                        Button {
                            strategy.tint = tint
                        } label: {
                            Circle()
                                .fill(tint.color)
                                .frame(width: 16, height: 16)
                                .padding(Theme.Spacing.xxs)
                                .overlay(
                                    Circle().strokeBorder(
                                        strategy.tint == tint ? Color.primary : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tint.rawValue)
                    }
                }
            }
            SettingsEditorField("Type") {
                SteadySegmentedPicker(
                    title: String(localized: "Type"),
                    options: ProxyStrategy.Kind.allCases.map { .init(value: $0, title: $0.title) },
                    selection: $strategy.kind)
            }
        } footer: {
            Text(strategy.kind.explanation).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var options: some View {
        Section {
            ForEach(Array(strategy.members.enumerated()), id: \.offset) { index, member in
                HStack {
                    Text(member.title(in: profile))
                    Spacer()
                    Button {
                        strategy.members.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Remove \(member.title(in: profile))"))
                }
            }
            Menu("Add Option") {
                ForEach(profile.strategies.filter { $0.id != strategy.id }) { other in
                    Button(other.name) { strategy.members.append(.strategy(other.id)) }
                        .disabled(strategy.members.contains(.strategy(other.id)))
                }
                Divider()
                Button("Direct") { strategy.members.append(.direct) }
                    .disabled(strategy.members.contains(.direct))
                Button("Reject") { strategy.members.append(.reject) }
                    .disabled(strategy.members.contains(.reject))
            }
            .fixedSize()
        } header: {
            Text("Options")
        } footer: {
            Text("Other strategies offered ahead of the nodes, in this order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nodes: some View {
        Section {
            Toggle("Include nodes from the pool", isOn: includesPool)
            if let pool = strategy.pool {
                Picker("Sources", selection: allSources) {
                    Text("All Sources").tag(true)
                    Text("Chosen Sources").tag(false)
                }
                if pool.sources != nil {
                    ForEach(profile.sources) { source in
                        Toggle(source.name, isOn: sourceBinding(source.id))
                            .toggleStyle(.checkbox)
                    }
                }
                LabeledContent("Regions") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 104), alignment: .leading)],
                            alignment: .leading
                        ) {
                            ForEach(offeredRegions, id: \.self) { region in
                                Toggle(region.label, isOn: regionBinding(region))
                                    .toggleStyle(.button)
                                    .controlSize(.small)
                            }
                        }
                        Text("None chosen takes every region.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsEditorField("Name Pattern") {
                    TextField(
                        "Name Pattern", text: poolText(\.pattern),
                        prompt: Text(ProxyPrompt.example("IPLC|专线"))
                    )
                    .settingsEditorTextField()
                }
                SettingsEditorField("Leave out") {
                    TextField(
                        "Leave out", text: poolText(\.exclude), prompt: Text(ProxyPrompt.example("0\\.1x|游戏"))
                    )
                    .settingsEditorTextField()
                }
            }
        } header: {
            Text("Nodes")
        } footer: {
            Text(matchSummary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var testing: some View {
        Section {
            SettingsEditorField("Test URL") {
                TextField("Test URL", text: $strategy.testURL).settingsEditorTextField()
            }
            Picker("Test every", selection: $strategy.testInterval) {
                Text("Minute").tag(60)
                Text("5 Minutes").tag(300)
                Text("10 Minutes").tag(600)
                Text("30 Minutes").tag(1800)
            }
            if strategy.kind == .urlTest {
                LabeledContent("Tolerance") {
                    HStack(spacing: Theme.Spacing.xs) {
                        TextField("Tolerance", value: $strategy.tolerance, format: .number.grouping(.never))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("ms").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Delay Tests")
        } footer: {
            Text("A switch needs a node faster by more than the tolerance, so it does not flap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pool bindings

    private var includesPool: Binding<Bool> {
        Binding(
            get: { strategy.pool != nil },
            set: { strategy.pool = $0 ? .everything : nil })
    }

    private var allSources: Binding<Bool> {
        Binding(
            get: { strategy.pool?.sources == nil },
            set: { strategy.pool?.sources = $0 ? nil : profile.sources.map(\.id) })
    }

    private func sourceBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { strategy.pool?.sources?.contains(id) == true },
            set: { on in
                var sources = strategy.pool?.sources ?? []
                sources.removeAll { $0 == id }
                if on { sources.append(id) }
                strategy.pool?.sources = profile.sources.map(\.id).filter(sources.contains)
            })
    }

    private func regionBinding(_ region: ProxyRegion) -> Binding<Bool> {
        Binding(
            get: { strategy.pool?.regions.contains(region) == true },
            set: { on in
                var regions = strategy.pool?.regions ?? []
                regions.removeAll { $0 == region }
                if on { regions.append(region) }
                strategy.pool?.regions = ProxyRegion.allCases.filter(regions.contains)
            })
    }

    private func poolText(_ keyPath: WritableKeyPath<ProxyStrategy.Pool, String>) -> Binding<String> {
        Binding(
            get: { strategy.pool?[keyPath: keyPath] ?? "" },
            set: { strategy.pool?[keyPath: keyPath] = $0 })
    }

    /// The regions the nodes are in, and any already chosen; every region until connected.
    private var offeredRegions: [ProxyRegion] {
        guard let snapshot = manager.snapshot else { return ProxyRegion.allCases }
        let present = Set(snapshot.nodes.values.compactMap(\.region))
        let chosen = Set(strategy.pool?.regions ?? [])
        return ProxyRegion.allCases.filter { present.contains($0) || chosen.contains($0) }
    }

    /// The pool as it would be with this draft, from the nodes the running core holds now.
    private var matchSummary: String {
        guard let pool = strategy.pool else {
            return String(localized: "Only the options above are offered.")
        }
        guard let snapshot = manager.snapshot else {
            return String(localized: "Connect to see which nodes match.")
        }
        let sources = pool.sources.map(Set.init)
        let names = snapshot.nodes.values
            .filter { node in sources.map { set in node.source.map(set.contains) ?? false } ?? true }
            .map(\.name).sorted()
        let admitted = pool.admitted(names)
        guard !admitted.isEmpty else { return String(localized: "No node matches yet.") }
        let sample = admitted.prefix(4).joined(separator: ", ") + (admitted.count > 4 ? "…" : "")
        return String(localized: "Matches \(admitted.count) nodes: \(sample)")
    }

    // MARK: - Saving

    private func save() {
        strategy.name = strategy.name.trimmingCharacters(in: .whitespaces)
        var candidate = profile
        if let index = candidate.strategies.firstIndex(where: { $0.id == strategy.id }) {
            candidate.strategies[index] = strategy
        } else {
            candidate.strategies.append(strategy)
        }
        if let problem = candidate.problems.first(where: { $0.subject == .strategy(strategy.id) }) {
            error = problem.message(in: candidate)
            return
        }
        let strategy = strategy
        let route = route
        guard
            coordinator.update({ profile in
                if let index = profile.strategies.firstIndex(where: { $0.id == strategy.id }) {
                    profile.strategies[index] = strategy
                } else {
                    profile.strategies.append(strategy)
                }
                guard let route else { return }
                if route == ProxyRoute.finalID {
                    profile.finalTarget = .strategy(strategy.id)
                } else if let index = profile.routes.firstIndex(where: { $0.id == route }) {
                    profile.routes[index].target = .strategy(strategy.id)
                }
            })
        else { return }
        close()
    }
}

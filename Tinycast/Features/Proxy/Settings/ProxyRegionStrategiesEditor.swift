import SwiftUI

/// A strategy for each chosen region at once, of one type, offered by the default if asked.
struct ProxyRegionStrategiesEditor: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    @State private var chosen: Set<ProxyRegion>
    @State private var kind = ProxyStrategy.Kind.urlTest
    @State private var offered = true

    /// A region this size merits a strategy of its own; a tail of one or two nodes rarely does.
    static let suggestedSize = 5

    init(manager: ProxyManager, close: @escaping () -> Void) {
        self.manager = manager
        self.close = close
        let profile = manager.store.profile
        let counts = Self.counts(in: manager.snapshot)
        let suggested = counts.filter { region, count in
            count >= Self.suggestedSize && profile.strategy(forRegion: region) == nil
        }
        _chosen = State(initialValue: Set(suggested.keys))
    }

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    /// The default strategy when the user picks in it; an automatic one would only test them.
    private var picker: ProxyStrategy? {
        profile.strategy(profile.defaultStrategy).flatMap { $0.kind == .select ? $0 : nil }
    }

    private var creatable: Set<ProxyRegion> {
        chosen.filter { profile.strategy(forRegion: $0) == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "New Strategies by Region",
                subtitle: "One strategy per region, from every source; nodes a subscription adds later join the right one."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            // The region list grows with the nodes, so the options go first to stay in view.
            Form {
                Section {
                    SettingsEditorField("Type") {
                        SteadySegmentedPicker(
                            title: String(localized: "Type"),
                            options: ProxyStrategy.Kind.allCases.map { .init(value: $0, title: $0.title) },
                            selection: $kind)
                    }
                } footer: {
                    Text(kind.explanation).font(.caption).foregroundStyle(.secondary)
                }

                if let picker {
                    Section {
                        Toggle("Offer them in \(picker.name)", isOn: $offered)
                    } footer: {
                        Text("They join its options, so a region is a click away there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    regions
                } header: {
                    regionsHeader
                } footer: {
                    Text("Regions of \(Self.suggestedSize) or more nodes start chosen; one with its own strategy is left alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Create \(creatable.count) Strategies", action: create)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(creatable.isEmpty)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 640)
        .settingsEditorPanelSurface()
    }

    /// The regions the nodes are in, the largest first; until connected there is nothing to count.
    @ViewBuilder private var regions: some View {
        let counts = Self.counts(in: manager.snapshot)
        if manager.snapshot == nil {
            Text("Connect to list the regions the nodes are in.").foregroundStyle(.secondary)
        } else if counts.isEmpty {
            Text("No node names a region.").foregroundStyle(.secondary)
        } else {
            ProxyChipGrid(minimumWidth: 150) {
                ForEach(Self.ordered(counts), id: \.self) { region in
                    regionChip(region, count: counts[region] ?? 0)
                }
            }
        }
    }

    private var regionsHeader: some View {
        let available = Self.counts(in: manager.snapshot).keys.filter {
            profile.strategy(forRegion: $0) == nil
        }
        let choosesAll = Set(available) != creatable
        return HStack {
            Text("Regions")
            Spacer()
            if !available.isEmpty {
                Button(choosesAll ? "Select All" : "Deselect All") {
                    chosen = choosesAll ? Set(available) : []
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func regionChip(_ region: ProxyRegion, count: Int) -> some View {
        let existing = profile.strategy(forRegion: region)
        let isOn = existing == nil && chosen.contains(region)
        let pick: (() -> Void)? = existing == nil ? { toggle(region) } : nil
        let help = existing.map { Text("“\($0.name)” takes this region's nodes already") } ?? Text(region.label)
        let note = existing.map { _ in Text("Exists") }
        ProxyChip(isCurrent: isOn, tint: .accentColor, delay: nil, note: note, pick: pick) {
            ProxyFlag(emoji: region.flagEmoji, size: NSFont.preferredFont(forTextStyle: .callout).pointSize)
            Text(region.title).lineLimit(1).layoutPriority(1)
            Text(count, format: .number).foregroundStyle(.secondary)
        }
        .opacity(existing == nil ? 1 : 0.6)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ region: ProxyRegion) {
        if chosen.contains(region) { chosen.remove(region) } else { chosen.insert(region) }
    }

    private func create() {
        let regions = creatable
        let kind = kind
        let offered = offered && picker != nil
        var count = 0
        guard
            coordinator.update({ profile in
                count = profile.addRegionStrategies(
                    regions, kind: kind, offeredByDefault: offered, named: \.label, newID: UUID.init
                ).count
            })
        else { return }
        core.showMessage(String(localized: "\(count) strategies created"), tone: .success)
        close()
    }

    private static func counts(in snapshot: ProxySnapshot?) -> [ProxyRegion: Int] {
        guard let snapshot else { return [:] }
        return Dictionary(grouping: snapshot.nodes.values.compactMap(\.region), by: \.self).mapValues(\.count)
    }

    /// The most nodes first, ties in the region table's order.
    private static func ordered(_ counts: [ProxyRegion: Int]) -> [ProxyRegion] {
        ProxyRegion.allCases.filter { counts[$0] != nil }.enumerated()
            .sorted { (counts[$1.element] ?? 0, $0.offset) < (counts[$0.element] ?? 0, $1.offset) }
            .map(\.element)
    }
}

import SwiftUI

/// The connections open now: what each matched, where it went out, and a rule for any of them.
struct ProxyActivityPane: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor
    let manager: ProxyManager
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var selection: Set<ProxyActivity.ID> = []

    enum Filter: Hashable, CaseIterable {
        case all
        case proxied
        case direct
        case rejected

        func includes(_ activity: ProxyActivity) -> Bool {
            switch self {
            case .all: true
            case .proxied: activity.target?.strategyID != nil
            case .direct: activity.target == .direct
            case .rejected: activity.target == .reject
            }
        }
    }

    /// Ideals that together fit the window's default width, so no column starts out of view.
    private enum Width {
        static let time = (min: 60.0, ideal: 70.0)
        static let destination = (min: 120.0, ideal: 170.0)
        static let app = (min: 50.0, ideal: 80.0)
        static let route = (min: 70.0, ideal: 90.0)
        static let exit = (min: 90.0, ideal: 120.0)
        static let data = (min: 54.0, ideal: 60.0)
    }

    private var profile: ProxyProfile { manager.store.profile }
    private var monitor: ProxyConnectionsMonitor { core.proxyCoordinator.connections }

    var body: some View {
        if manager.isRunning {
            VStack(spacing: 0) {
                bar
                table
            }
        } else {
            ProxyPage {
                ProxyNote(text: String(localized: "Once connected, every connection is listed here with the route it matched and where it went out."))
            }
        }
    }

    private var activities: [ProxyActivity] {
        monitor.connections.map { ProxyActivity($0, profile: profile) }
    }

    private var bar: some View {
        let all = activities
        return HStack(spacing: Theme.Spacing.md) {
            Picker(selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Text("\(title(of: filter)) \(all.filter(filter.includes).count)").tag(filter)
                }
            } label: {
                Text("Show")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            TextField("Search", text: $search, prompt: Text("Domain or app"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Spacer()
            if monitor.hasLoaded {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(Theme.Colors.success)
                        .frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
                    Text("Live")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var table: some View {
        let rows = activities.filter { filter.includes($0) && matches($0) }
        return Table(rows, selection: $selection) {
            TableColumn("Time") { activity in
                Text(activity.start.map { $0.formatted(date: .omitted, time: .standard) } ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: Width.time.min, ideal: Width.time.ideal)
            TableColumn("Destination") { activity in
                Text(activity.host).lineLimit(1).truncationMode(.middle).help(activity.host)
            }
            .width(min: Width.destination.min, ideal: Width.destination.ideal)
            TableColumn("App") { activity in
                Text(activity.process.isEmpty ? "—" : activity.process).lineLimit(1)
            }
            .width(min: Width.app.min, ideal: Width.app.ideal)
            TableColumn("Route") { activity in
                Text(matchTitle(activity.match)).lineLimit(1)
            }
            .width(min: Width.route.min, ideal: Width.route.ideal)
            TableColumn("Exit") { activity in
                // The node alone fits; the dot's colour and the tooltip name the strategy.
                HStack(spacing: Theme.Spacing.sm) {
                    if let target = activity.target { ProxyTargetDot(target: target, profile: profile) }
                    Text(exitNode(activity) ?? exitTitle(activity)).lineLimit(1).truncationMode(.middle)
                }
                .help(exitTitle(activity))
            }
            .width(min: Width.exit.min, ideal: Width.exit.ideal)
            TableColumn("Data") { activity in
                Text((activity.upload + activity.download).formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: Width.data.min, ideal: Width.data.ideal)
        }
        .contextMenu(forSelectionType: ProxyActivity.ID.self) { ids in
            if let activity = rows.first(where: { ids.contains($0.id) }) {
                Button("Add Rule for \(activity.host)…") {
                    openEditor(.quickRule(host: activity.host, process: activity.process, current: activity.target))
                }
                Button("Copy Destination") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(activity.host, forType: .string)
                }
                Divider()
                Button("Close Connection") {
                    Task { await monitor.close(activity.id) }
                }
            }
        }
        .overlay {
            if monitor.hasLoaded, rows.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Text(search.isEmpty ? "No connections right now" : "No matching connections")
                    // Without TUN nothing reaches the core unless an app was pointed at the port.
                    if search.isEmpty, manager.isRunning, !manager.isTUN {
                        Text("Without TUN, only apps set to use port \(String(profile.general.mixedPort)) show here.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
    }

    private func matches(_ activity: ProxyActivity) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return activity.host.localizedCaseInsensitiveContains(query)
            || activity.process.localizedCaseInsensitiveContains(query)
    }

    private func title(of filter: Filter) -> String {
        switch filter {
        case .all: String(localized: "All")
        case .proxied: String(localized: "Proxied")
        case .direct: String(localized: "Direct")
        case .rejected: String(localized: "Rejected")
        }
    }

    private func matchTitle(_ match: ProxyActivity.Match) -> String {
        switch match {
        case .rule(let id): profile.rules.first { $0.id == id }?.value ?? String(localized: "My Rules")
        case .route(let id) where id == ProxyRoute.finalID: ProxyRoute.finalTitle
        case .route(let id): profile.routes.first { $0.id == id }?.title ?? id
        case .mode: manager.mode.title
        case .core: String(localized: "Core")
        case .unknown: "—"
        }
    }

    private func exitTitle(_ activity: ProxyActivity) -> String {
        guard let target = activity.target else { return exitNode(activity) ?? "—" }
        let name = target.title(in: profile)
        guard let node = exitNode(activity) else { return name }
        return "\(name) › \(node)"
    }

    private func exitNode(_ activity: ProxyActivity) -> String? {
        activity.node.map { manager.snapshot?.nodes[$0]?.label ?? $0 }
    }
}

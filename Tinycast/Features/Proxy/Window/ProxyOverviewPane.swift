import SwiftUI

/// Where traffic goes now: the default strategy's exit, the rates, the flow map and the status.
struct ProxyOverviewPane: View {
    @Environment(AppCore.self) private var core
    @Environment(ProxyWindowState.self) private var state
    let manager: ProxyManager
    @State private var siteTest: ProxySiteTest?

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        if profile.sources.isEmpty {
            ProxyOnboarding(manager: manager)
        } else {
            ProxyPage {
                HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                    ProxyExitCard(manager: manager)
                    ProxyTrafficCard(traffic: coordinator.traffic, isConnected: manager.isRunning)
                }
                ProxyCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Flow").font(.headline)
                            Text(flowCaption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button("Edit Routing") { state.page = .routes }
                        }
                        ProxyFlowTest(manager: manager, test: $siteTest)
                        ProxyFlowMap(
                            profile: profile, mode: manager.mode, snapshot: manager.snapshot,
                            isConnected: manager.isRunning, highlight: highlight
                        ) { destination in
                            switch destination {
                            case .routes: state.page = .routes
                            case .strategy(let id):
                                state.nodesStrategy = id
                                state.page = .nodes
                            }
                        }
                    }
                }
                ProxyStatusTiles(manager: manager)
            }
        }
    }

    private var highlight: ProxyFlow.Highlight? {
        guard case .found(let probe) = siteTest else { return nil }
        return probe.highlight(in: profile, mode: manager.mode)
    }

    private var flowCaption: String {
        guard manager.isRunning else { return String(localized: "Not connected; traffic will go as shown.") }
        switch manager.mode {
        case .rule: return String(localized: "My rules first, then the routes from top to bottom.")
        case .global: return String(localized: "Global mode: everything takes the default strategy.")
        case .direct: return String(localized: "Direct mode: nothing goes through a node.")
        }
    }
}

/// The default strategy's exit now, and the connection behind it.
private struct ProxyExitCard: View {
    @Environment(AppCore.self) private var core
    @Environment(ProxyWindowState.self) private var state
    let manager: ProxyManager

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Exit").font(.caption).foregroundStyle(.secondary)
                if manager.isRunning {
                    connected
                } else {
                    disconnected
                }
            }
        }
    }

    @ViewBuilder private var connected: some View {
        let strategy = profile.strategy(profile.defaultStrategy)
        let target = ProxyTarget.strategy(profile.defaultStrategy)
        let reach = manager.snapshot?.reach(from: profile.defaultStrategy, in: profile)
        Group {
            if manager.mode != .direct, let node = reach?.node {
                ProxyNodeLabel(node: node, size: NSFont.preferredFont(forTextStyle: .title2).pointSize)
            } else if manager.mode == .direct {
                Text("Direct")
            } else {
                Text(reach?.outcome?.title(in: profile) ?? String(localized: "No node picked"))
            }
        }
        .font(.title2.weight(.semibold))
        .lineLimit(1)
        HStack(spacing: Theme.Spacing.sm) {
            if manager.mode != .direct {
                ProxyTargetDot(target: target, profile: profile)
                if let strategy { ProxyStrategyName(strategy: strategy) }
                if let node = reach?.node { ProxyDelayText(delay: node.delay(for: strategy?.testURL)) }
            }
            // Refreshed on a timer, since nothing else changes while the connection just runs on.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(connectionDetail(at: context.date)).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        HStack {
            Button("Choose Node") {
                state.nodesStrategy = nil
                state.page = .nodes
            }
            Button("Test Delays") { core.proxyCoordinator.testDelays(of: profile.defaultStrategy) }
                .disabled(manager.testingStrategies.contains(profile.defaultStrategy))
        }
    }

    @ViewBuilder private var disconnected: some View {
        Text(manager.statusTitle).font(.title2.weight(.semibold))
        if case .failed(let failure) = manager.status {
            Text(failure.message(in: profile))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        } else {
            Text("Connect to send traffic through the routes below.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Button("Connect") { core.proxyCoordinator.connect() }
            .disabled(manager.status == .starting)
    }

    private func connectionDetail(at now: Date) -> String {
        guard case .running(let since) = manager.status else { return "" }
        let elapsed = now.timeIntervalSince(since)
        let time =
            elapsed < 60
            ? String(localized: "Just connected")
            : String(localized: "Connected for \(Duration.seconds(elapsed).formatted(Self.elapsedStyle))")
        let way = manager.isTUN ? "TUN" : String(localized: "Port \(String(profile.general.mixedPort))")
        return way + " · " + time
    }

    private static let elapsedStyle = Duration.UnitsFormatStyle(
        allowedUnits: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
}

/// Upload and download rates, with the last minute drawn behind them.
private struct ProxyTrafficCard: View {
    let traffic: ProxyTrafficMonitor
    let isConnected: Bool

    var body: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Traffic").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.xxl) {
                    rate(symbol: "arrow.down", value: traffic.current?.down, color: Theme.Colors.primaryAction)
                    rate(symbol: "arrow.up", value: traffic.current?.up, color: Theme.Colors.success)
                }
                ProxySparkline(samples: traffic.recent)
                    .frame(height: 44)
                if let current = traffic.current, let down = current.downTotal, let up = current.upTotal {
                    Text("\(down.formatted(.byteCount(style: .file))) down, \(up.formatted(.byteCount(style: .file))) up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 300)
    }

    private func rate(symbol: String, value: Int64?, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            SymbolImage(name: symbol, size: Theme.Size.settingsSidebarGlyph).foregroundStyle(color)
            Text(value.map(ProxyRate.text) ?? "—")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bytes a second, as `1.2 MB/s`.
enum ProxyRate {
    static func text(_ bytesPerSecond: Int64) -> String {
        String(localized: "\(bytesPerSecond.formatted(.byteCount(style: .file)))/s")
    }
}

/// The last minute of download and upload, scaled to the busiest second.
private struct ProxySparkline: View {
    let samples: [ProxyAPI.Traffic]

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let peak = Double(max(samples.map { max($0.down, $0.up) }.max() ?? 1, 1))
            let step = size.width / Double(ProxyTrafficMonitor.historyLength - 1)
            let offset = Double(ProxyTrafficMonitor.historyLength - samples.count) * step
            func line(_ value: (ProxyAPI.Traffic) -> Int64) -> Path {
                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let point = CGPoint(
                        x: offset + Double(index) * step, y: size.height * (1 - Double(value(sample)) / peak))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                return path
            }
            context.stroke(line(\.down), with: .color(Theme.Colors.primaryAction), lineWidth: 1.5)
            context.stroke(line(\.up), with: .color(Theme.Colors.success.opacity(0.8)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Rule sets, sources and the core, each with the one action it most often needs.
private struct ProxyStatusTiles: View {
    @Environment(AppCore.self) private var core
    @Environment(ProxyWindowState.self) private var state
    let manager: ProxyManager

    private var profile: ProxyProfile { manager.store.profile }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            tile(title: String(localized: "Rule Sets"), detail: ruleSetDetail) {
                Button("Update Now") { coordinator.updateRuleSets() }
                    .disabled(!manager.isRunning || manager.isUpdatingRuleSets)
            }
            tile(title: String(localized: "Nodes"), detail: nodeDetail) {
                Button("Subscriptions") { state.page = .sources }
            }
            tile(title: String(localized: "Core"), detail: coreDetail) {
                if manager.helper.state != .ready, profile.general.usesTUN {
                    Button("Install TUN Helper…") { coordinator.installHelper() }
                } else {
                    Button("Settings…") { coordinator.openSettings(revealing: .proxyCore) }
                }
            }
        }
    }

    private func tile<Accessory: View>(
        title: String, detail: String, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(detail).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                accessory()
            }
        }
    }

    private var ruleSetDetail: String {
        guard let ruleSets = manager.snapshot?.ruleSets, !ruleSets.isEmpty else {
            return String(localized: "Downloaded once connected.")
        }
        let loaded = ruleSets.values.filter { $0.rules > 0 }.count
        let updated = ruleSets.values.compactMap(\.updatedAt).max()
        let count = String(localized: "\(loaded) of \(ruleSets.count) rule sets loaded")
        guard let updated else { return count }
        return count + " · " + String(localized: "Updated \(updated.formatted(.relative(presentation: .named)))")
    }

    private var nodeDetail: String {
        let sources = profile.sources.filter(\.isEnabled).count
        guard let snapshot = manager.snapshot else {
            return String(localized: "\(sources) sources in use")
        }
        return String(localized: "\(snapshot.nodes.count) nodes from \(sources) sources")
    }

    private var coreDetail: String {
        let version = manager.coreVersion.map { "mihomo \($0)" } ?? "mihomo"
        guard manager.isRunning else { return version }
        return manager.isTUN
            ? String(localized: "\(version) · TUN")
            : String(localized: "\(version) · port \(String(profile.general.mixedPort))")
    }
}

import SwiftUI

/// What a site test found, kept until the next test, a clear, or a change to where traffic goes.
enum ProxySiteTest: Equatable {
    case found(ProxyProbe)
    case failed(String)
}

/// A site test above the flow map: type a site or address, and the map lights the path it takes.
struct ProxyFlowTest: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    @Binding var test: ProxySiteTest?
    @State private var input = ""
    @State private var isRunning = false
    /// The test in flight; a result is applied only while it is still the latest.
    @State private var operation: UUID?

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                SymbolImage(name: "magnifyingglass", size: Theme.Size.settingsSidebarGlyph)
                    .foregroundStyle(.secondary)
                TextField("Test a Site", text: $input, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .onSubmit(run)
                    .disabled(!manager.isRunning)
                if isRunning {
                    ProgressView().controlSize(.small)
                } else if test != nil {
                    Button {
                        clear()
                    } label: {
                        SymbolImage(name: "xmark.circle.fill", size: Theme.Size.settingsSidebarGlyph)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Clear"))
                    .accessibilityLabel(Text("Clear"))
                }
                Button("Test", action: run)
                    .disabled(!manager.isRunning || isRunning || ProxyProbe.Destination(input) == nil)
            }
            .padding(.leading, Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.xs)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
            switch test {
            case .found(let probe):
                ProxyTestPath(probe: probe, profile: profile, mode: manager.mode, snapshot: manager.snapshot)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
        .onChange(of: manager.mode) { clear() }
        .onChange(of: manager.isRunning) { clear() }
    }

    private var prompt: String {
        manager.isRunning
            ? String(localized: "A site or IP address, to see the path it takes")
            : String(localized: "Connect to test the path a site takes")
    }

    private func clear() {
        operation = nil
        isRunning = false
        test = nil
    }

    private func run() {
        guard manager.isRunning, !isRunning, let destination = ProxyProbe.Destination(input) else { return }
        let token = UUID()
        operation = token
        isRunning = true
        test = nil
        Task {
            let result = await core.proxyCoordinator.probe(destination)
            guard operation == token else { return }
            isRunning = false
            switch result {
            case .success(let outcome): test = .found(ProxyProbe(destination: destination, outcome: outcome))
            case .failure(.unreachable): test = .failed(String(localized: "The core could not be reached."))
            case .failure(.noRecord):
                test = .failed(String(localized: "The core reported nothing for this site in time."))
            }
        }
    }
}

/// The test's path in words: the site, the rule or route it matched, the strategy, the exit.
private struct ProxyTestPath: View {
    let probe: ProxyProbe
    let profile: ProxyProfile
    let mode: ProxyMode
    let snapshot: ProxySnapshot?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(probe.destination.host).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            switch probe.outcome {
            case .matched(let rule, let payload, let exit):
                arrow
                Text(matchTitle(rule: rule, payload: payload)).lineLimit(1)
                if let target, target.strategyID != nil {
                    arrow
                    targetStep(target)
                }
                arrow
                exitStep(exit)
            case .mode:
                arrow
                Text(mode == .global ? String(localized: "Global mode") : String(localized: "Direct mode"))
                if mode == .global {
                    arrow
                    targetStep(.strategy(profile.defaultStrategy))
                    if let node = snapshot?.node(reachedBy: profile.defaultStrategy, in: profile) {
                        arrow
                        ProxyNodeLabel(node: node, showsNote: false)
                    }
                }
            case .failed(let rule, let payload, let reason):
                arrow
                Text(matchTitle(rule: rule, payload: payload)).lineLimit(1)
                arrow
                Label("Could not connect", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Colors.destructive)
                    .help(Text(reason))
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private var arrow: some View {
        SymbolImage(name: "arrow.right", size: Theme.Size.settingsSidebarGlyph * 0.85)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func targetStep(_ target: ProxyTarget) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ProxyTargetDot(target: target, profile: profile)
            ProxyTargetName(target: target, profile: profile)
        }
    }

    @ViewBuilder private func exitStep(_ exit: String) -> some View {
        if let node = snapshot?.nodes[exit] {
            ProxyNodeLabel(node: node, showsNote: false)
        } else {
            Text(ProxyPaletteRows.optionTitle(exit)).lineLimit(1)
        }
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

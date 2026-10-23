import SwiftUI

/// A route made from a rule-set link of the user's own, read first to tell its format and kind.
struct ProxyCustomRouteEditor: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    private let routeID: String?
    @State private var name: String
    @State private var link: String
    @State private var format: ProxyRuleSet.Format
    @State private var behavior: ProxyRuleSet.Behavior
    @State private var target: ProxyTarget
    @State private var detection: Detection = .none
    @State private var error: String?

    private enum Detection: Equatable {
        case none
        case reading
        case read(entries: Int?)
        case unreadable(String)
    }

    init(routeID: String?, link: String, manager: ProxyManager, close: @escaping () -> Void) {
        self.manager = manager
        self.close = close
        self.routeID = routeID
        let profile = manager.store.profile
        let route = profile.routes.first { $0.id == routeID }
        var name = ""
        var ruleSet: ProxyRuleSet?
        if case .custom(let routeName, let ruleSets) = route?.kind {
            name = routeName
            ruleSet = ruleSets.first
        }
        _name = State(initialValue: name)
        _link = State(initialValue: link)
        _format = State(initialValue: ruleSet?.format ?? .text)
        _behavior = State(initialValue: ruleSet?.behavior ?? .domain)
        _target = State(initialValue: route?.target ?? .strategy(profile.defaultStrategy))
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: routeID == nil ? "Add Rule Set" : "Edit Rule Set",
                subtitle: "A list of domains or addresses kept up to date at a link."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    SettingsEditorField("Link") {
                        // Verbatim: a literal is read as Markdown, which would style the URL.
                        TextField(
                            "Link", text: $link, prompt: Text(verbatim: "https://example.com/rules.yaml")
                        )
                        .settingsEditorTextField()
                        .frame(width: 360)
                        .onSubmit { Task { await detect() } }
                    }
                    SettingsEditorField("Name") {
                        TextField(
                            "Name", text: $name,
                            prompt: Text(ProxyPrompt.example(String(localized: "Work Sites")))
                        )
                        .settingsEditorTextField()
                        .frame(width: 360)
                    }
                    Picker("Holds", selection: $behavior) {
                        Text("Domains").tag(ProxyRuleSet.Behavior.domain)
                        Text("Address Ranges").tag(ProxyRuleSet.Behavior.ipcidr)
                        if format != .mrs { Text("Mixed Rules").tag(ProxyRuleSet.Behavior.classical) }
                    }
                    ProxyTargetPicker(
                        title: String(localized: "Goes to"), target: $target, profile: manager.store.profile)
                } footer: {
                    detectionNote
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
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
                Button(routeID == nil ? "Add" : "Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(detection == .reading)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 560, height: 460)
        .settingsEditorPanelSurface()
        .task {
            guard routeID == nil, !link.isEmpty else { return }
            await detect()
        }
    }

    @ViewBuilder private var detectionNote: some View {
        switch detection {
        case .none:
            Text("The link is read when added, to tell its format and what it holds.")
        case .reading:
            Text("Reading the link…")
        case .read(let entries?):
            Text("Read as \(format.title) with \(entries) entries at the start. Change what it holds if this is wrong.")
        case .read(nil):
            Text("Read as \(format.title). Its entries are compressed, so what it holds is told from the link's path.")
        case .unreadable(let reason):
            Text("The link could not be read (\(reason)). The format follows its extension; check what it holds.")
        }
    }

    /// Reads the link through the proxy when connected, since rule sets are often hosted abroad.
    private func detect() async {
        let normalized = ProxyRuleSetDetection.normalize(link)
        guard ProxyText.isWebURL(normalized) else { return }
        link = normalized
        detection = .reading
        let port = manager.isRunning ? manager.store.profile.general.mixedPort : nil
        let result: ProxyRuleSetDetection
        do {
            let sample = try await ProxyRuleSetFetcher.sample(of: normalized, proxyPort: port)
            result = ProxyRuleSetDetection.detect(link: normalized, sample: sample.data, isComplete: sample.isComplete)
            detection = .read(entries: result.entries)
        } catch {
            result = ProxyRuleSetDetection.guess(link: normalized)
            detection = .unreadable(Self.reason(error))
        }
        guard link == normalized else { return }
        format = result.format
        behavior = result.behavior
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = result.name }
    }

    /// Without its closing stop, since the note puts it in parentheses mid-sentence.
    private static func reason(_ error: any Error) -> String {
        let reason =
            switch error {
            case ProxyRuleSetFetcher.Failure.status(let status): "HTTP \(status)"
            case ProxyRuleSetFetcher.Failure.unreachable(let message): message
            default: error.localizedDescription
            }
        return reason.trimmingCharacters(in: CharacterSet(charactersIn: ".。 "))
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespaces)
        let link = ProxyRuleSetDetection.normalize(link)
        guard ProxyText.isWebURL(link) else {
            error = String(localized: "Enter the rule set's link, starting with https://.")
            return
        }
        guard format != .mrs || behavior != .classical else {
            error = String(localized: "A .mrs rule set holds only domains or only address ranges.")
            return
        }
        let id = routeID ?? ProxyRoute.newCustomID()
        let ruleSet = ProxyRuleSet(
            name: id + "-1", behavior: behavior, format: format, location: .url(link), resolves: false)
        var route = ProxyRoute(
            id: id, kind: .custom(name: name, ruleSets: [ruleSet]), target: target, isEnabled: true)
        var candidate = manager.store.profile
        if let index = candidate.routes.firstIndex(where: { $0.id == id }) {
            route.isEnabled = candidate.routes[index].isEnabled
            candidate.routes[index] = route
        } else {
            candidate.addRoute(route)
        }
        if let problem = candidate.problems.first(where: { $0.subject == .route(id) }) {
            error = problem.message(in: candidate)
            return
        }
        let routes = candidate.routes
        guard core.proxyCoordinator.update({ $0.routes = routes }) else { return }
        close()
    }
}

extension ProxyRuleSet.Format {
    var title: String {
        switch self {
        case .mrs: "MRS"
        case .yaml: "YAML"
        case .text: String(localized: "a plain list")
        }
    }
}

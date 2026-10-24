import SwiftUI

/// The user's own rules: each sends one domain, address range or app to a target, before any route.
struct ProxyRulesEditor: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    @State private var rules: [ProxyUserRule]
    @State private var kind = ProxyUserRule.Kind.domainSuffix
    @State private var value = ""
    @State private var target: ProxyTarget
    @State private var error: String?
    @State private var test = ""

    init(manager: ProxyManager, close: @escaping () -> Void) {
        self.manager = manager
        self.close = close
        _rules = State(initialValue: manager.store.profile.rules)
        _target = State(initialValue: .strategy(manager.store.profile.defaultStrategy))
    }

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "My Rules",
                subtitle: "Matched top to bottom, before every route."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    Picker("Match", selection: $kind) {
                        ForEach(ProxyUserRule.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    SettingsEditorField("Value") {
                        TextField("Value", text: $value, prompt: Text(ProxyPrompt.example(kind.prompt)))
                            .settingsEditorTextField()
                            .onSubmit(add)
                    }
                    ProxyTargetPicker(title: String(localized: "Goes to"), target: $target, profile: profile)
                    HStack {
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        Spacer()
                        Button("Add Rule", action: add)
                            .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("New Rule")
                } footer: {
                    Text("A pasted address keeps only its host. New rules go first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if rules.isEmpty {
                        Text("No rules yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        ruleRow(rule, at: index)
                    }
                } header: {
                    Text("\(rules.count) Rules")
                }

                Section {
                    SettingsEditorField("Domain or IP") {
                        TextField(
                            "Domain or IP", text: $test, prompt: Text(ProxyPrompt.example("chat.openai.com"))
                        )
                        .settingsEditorTextField()
                    }
                    Text(testResult)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Test")
                } footer: {
                    Text("Checks only the rules above, saved or not; the site test on the Overview asks the core.")
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
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 680)
        .settingsEditorPanelSurface()
    }

    private func ruleRow(_ rule: ProxyUserRule, at index: Int) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Toggle("", isOn: $rules[index].isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel(String(localized: "Use \(rule.value)"))
            Text(rule.kind.title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(rule.value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            ProxyTargetPicker(title: rule.value, target: $rules[index].target, profile: profile)
                .labelsHidden()
                .fixedSize()
            Menu {
                Button("Move Up") { rules.swapAt(index, index - 1) }.disabled(index == 0)
                Button("Move Down") { rules.swapAt(index, index + 1) }.disabled(index == rules.count - 1)
                Divider()
                Button("Delete", role: .destructive) { rules.remove(at: index) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(localized: "Actions for \(rule.value)"))
        }
        .proxyDimmed(!rule.isEnabled)
    }

    private var testResult: String {
        let input = test.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return String(localized: "Type a domain or an IP address.") }
        guard let match = ProxyRuleMatch.firstMatch(in: rules, for: input),
            let position = rules.firstIndex(where: { $0.id == match.id })
        else { return String(localized: "No rule matches; the routes decide.") }
        return String(localized: "Rule \(position + 1) matches → \(match.target.title(in: profile))")
    }

    private func add() {
        guard let normalized = ProxyUserRule.normalize(value, as: kind) else {
            error = kind.invalidValueMessage
            return
        }
        error = nil
        rules.insert(
            ProxyUserRule(id: UUID(), kind: kind, value: normalized, target: target, isEnabled: true), at: 0)
        value = ""
    }

    private func save() {
        let rules = rules
        guard core.proxyCoordinator.update({ $0.rules = rules }) else { return }
        close()
    }
}

/// Any strategy, Direct or Reject, as a pop-up menu.
struct ProxyTargetPicker: View {
    let title: String
    @Binding var target: ProxyTarget
    let profile: ProxyProfile

    var body: some View {
        Picker(selection: $target) {
            ForEach(profile.strategies) { strategy in
                Text(strategy.name).tag(ProxyTarget.strategy(strategy.id))
            }
            Divider()
            Text("Direct").tag(ProxyTarget.direct)
            Text("Reject").tag(ProxyTarget.reject)
        } label: {
            Text(title)
        }
    }
}

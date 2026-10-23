import SwiftUI

/// A rule for one connection from the activity page: how to match it, and where it should go.
struct ProxyQuickRuleEditor: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let close: () -> Void
    private let candidates: [(kind: ProxyUserRule.Kind, value: String)]
    @State private var choice: Int
    @State private var target: ProxyTarget

    private static let width = 460.0

    /// Starts on the other side of `current`, since the rule is there to send it elsewhere.
    init(
        host: String, process: String, current: ProxyTarget?, manager: ProxyManager, close: @escaping () -> Void
    ) {
        self.manager = manager
        self.close = close
        let byApp = process.isEmpty ? [] : [(kind: ProxyUserRule.Kind.processName, value: process)]
        candidates = ProxyUserRule.candidates(for: host) + byApp
        _choice = State(initialValue: 0)
        let proxied = current?.strategyID != nil
        _target = State(initialValue: proxied ? .direct : .strategy(manager.store.profile.defaultStrategy))
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(title: "Add Rule", subtitle: "New rules are matched before every route.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.dialogInset)
                .padding(.top, Theme.Spacing.dialogInset)
                .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    Picker("Match", selection: $choice) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                            Text(candidate.kind.description(of: candidate.value)).tag(index)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    ProxyTargetPicker(
                        title: String(localized: "Goes to"), target: $target, profile: manager.store.profile)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule", action: add)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(candidates.isEmpty)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: Self.width)
        .settingsEditorPanelSurface()
    }

    private func add() {
        guard candidates.indices.contains(choice) else { return }
        let candidate = candidates[choice]
        core.proxyCoordinator.addRule(candidate.kind, candidate.value, to: target)
        close()
    }
}

import SwiftUI

/// Settings › Proxy holds preferences; nodes, routing and subscriptions live in the proxy window.
struct ProxySettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var editor: ProxyEditor?

    var body: some View {
        let manager = core.proxy
        Form {
            Section {
                Toggle(isOn: enabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .proxyProxy, title: "Proxy",
                        subtitle: "Switch nodes and routing from the launcher, the menu bar or the proxy window.")
                }
                SettingsRow(
                    title: "Proxy Window",
                    subtitle: String(localized: "Nodes, strategies, routing, subscriptions and activity."),
                    anchor: .proxyWindow
                ) {
                    Button("Open…") { core.proxyCoordinator.showWindow() }
                        .disabled(!manager.store.profile.isEnabled)
                }
            }
            .settingsAnchor(.proxyProxy)

            ProxyGeneralPage(manager: manager, open: { editor = $0 })
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.proxy)
        .settingsEditorPanel(item: $editor) { editor in
            ProxyEditorPanel(
                editor: editor, manager: manager, replace: { self.editor = $0 }, close: { self.editor = nil })
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { core.proxy.store.profile.isEnabled },
            set: { core.proxyCoordinator.setEnabled($0) })
    }
}

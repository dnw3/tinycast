import SwiftUI

/// Live proxy preferences run in the same process as the connection.
struct ProxySettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(\.proxyOpenEditor) private var openEditor

    var body: some View {
        let manager = core.proxy
        Form {
            Section {
                Toggle(isOn: enabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .proxyProxy, title: "Proxy",
                        subtitle: "Switch nodes and routing from the launcher, the menu bar or the proxy window.")
                }
            }
            .settingsAnchor(.proxyProxy)

            ProxyGeneralPage(manager: manager, open: { openEditor($0) })
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.proxy)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { core.proxy.store.profile.isEnabled },
            set: { core.proxyCoordinator.setEnabled($0) })
    }
}

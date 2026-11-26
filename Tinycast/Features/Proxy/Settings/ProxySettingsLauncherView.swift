import SwiftUI

struct ProxySettingsLauncherView: View {
    @Environment(MainAppLink.self) private var mainApp
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { mainApp.status.proxyEnabled },
                    set: { mainApp.send(.setProxyEnabled($0)) }
                )) {
                    SettingsFeatureToggleLabel(
                        anchor: .proxyProxy, title: "Proxy",
                        subtitle: "Switch nodes and routing from the launcher, the menu bar or the proxy window.")
                }
                SettingsRow(
                    title: "Proxy Window",
                    subtitle: String(localized: "Nodes, strategies, routing, subscriptions and activity."),
                    anchor: .proxyWindow
                ) {
                    Button("Open…") { mainApp.send(.showProxyWindow) }
                    Button("Settings") { mainApp.send(.showProxySettings(nil)) }
                }
            }
            .settingsAnchor(.proxyProxy)
            FeatureCommandsSection(owner: .proxy, anchor: .proxyCommands)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.proxy)
        .onChange(of: navigation.scrollRequest, initial: true) { _, request in
            guard let request, request.target.tab == .proxy,
                ![.proxyProxy, .proxyWindow, .proxyCommands].contains(request.target.anchor)
            else { return }
            navigation.clear(request)
            mainApp.send(.showProxySettings(request.target))
        }
    }
}

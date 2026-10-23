import SwiftUI

/// Connection, the menu bar, DNS, the core, subscription updates and what lies past them.
struct ProxyGeneralPage: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let open: (ProxyEditor) -> Void

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var general: ProxyGeneral { manager.store.profile.general }

    var body: some View {
        connection
        menuBar
        ProxyTUNSection(manager: manager)
        dns
        ProxyCoreSection(manager: manager)
        updates
        advanced
        FeatureCommandsSection(owner: .proxy, anchor: .proxyCommands)
    }

    // MARK: - Connection

    private var connection: some View {
        Section {
            SettingsRow(title: statusTitle, subtitle: statusSubtitle, subtitleLineLimit: 3) {
                Button(manager.store.wantsConnection ? "Disconnect" : "Connect") {
                    if manager.store.wantsConnection {
                        coordinator.disconnect()
                    } else {
                        coordinator.connect()
                    }
                }
                .disabled(!manager.store.profile.isEnabled)
            }
            Toggle(isOn: setting(\.connectsAtLogin)) {
                SettingsRowTitle(.proxyConnection, "Connect when Tinycast starts")
                Text("Restores the connection you last left on.")
            }
            Toggle(isOn: setting(\.staysConnectedAfterQuit)) {
                SettingsRowTitle(.proxyConnection, "Stay connected after quitting")
                Text("Quitting or updating Tinycast leaves the network as it is. Needs the TUN helper.")
            }
        } header: {
            SettingsSectionHeader(.proxyConnection)
        }
        .settingsEnabled(manager.store.profile.isEnabled)
    }

    private var statusTitle: String { manager.statusTitle }

    private var statusSubtitle: String? {
        switch manager.status {
        case .off:
            return manager.store.profile.sources.isEmpty
                ? String(localized: "Add a subscription or a node file in the proxy window first.") : nil
        case .starting:
            return nil
        case .running(let since):
            let time = since.formatted(date: .omitted, time: .shortened)
            if manager.isTUN { return String(localized: "Since \(time) · TUN") }
            return String(localized: "Since \(time) · mixed port \(String(general.mixedPort))")
        case .failed(let failure):
            return failure.message(in: manager.store.profile)
        }
    }

    // MARK: - Menu bar

    private var menuBar: some View {
        Section {
            Toggle(isOn: setting(\.showsMenuBarItem)) {
                SettingsRowTitle(.proxyMenuBar, "Show in the menu bar")
                Text("The connection, the mode and each strategy's node, a click away.")
            }
            .settingsEnabled(manager.store.profile.isEnabled)
            Toggle(isOn: setting(\.showsMenuBarSpeed)) {
                SettingsRowTitle(.proxyMenuBar, "Show speed in the menu bar")
                Text("Download and upload rates beside the icon while connected.")
            }
            .settingsEnabled(manager.store.profile.isEnabled && general.showsMenuBarItem)
        } header: {
            SettingsSectionHeader(.proxyMenuBar)
        }
    }

    // MARK: - DNS

    private var dns: some View {
        Section {
            Picker(selection: setting(\.dnsMode)) {
                Text("Fake-IP (Recommended)").tag(ProxyGeneral.DNSMode.fakeIP)
                Text("Real IP").tag(ProxyGeneral.DNSMode.realIP)
            } label: {
                SettingsRowTitle(.proxyDNS, "DNS Mode")
                Text("Fake-IP answers at once and cannot be poisoned.")
            }
            ProxyServerListField(title: "Domestic DNS", servers: setting(\.domesticDNS)) {
                SettingsRowTitle(.proxyDNS, "Domestic DNS")
                Text("Resolves the domains that go direct.")
            }
            ProxyServerListField(title: "Overseas DNS", servers: setting(\.foreignDNS)) {
                SettingsRowTitle(.proxyDNS, "Overseas DNS")
                Text("Resolves the rest through the default strategy.")
            }
        } header: {
            SettingsSectionHeader(.proxyDNS)
        } footer: {
            Text(
                "DNS follows the routes: direct domains use the domestic servers, proxied ones are resolved through the proxy, so neither leaks."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Updates

    private var updates: some View {
        Section {
            Picker(selection: setting(\.subscriptionUpdateInterval)) {
                Text("Never").tag(0)
                Text("Every 6 Hours").tag(21_600)
                Text("Every 12 Hours").tag(43_200)
                Text("Every Day").tag(86_400)
                Text("Every 3 Days").tag(259_200)
            } label: {
                SettingsRowTitle(.proxyUpdates, "Update subscriptions")
            }
            Toggle(isOn: setting(\.updatesSubscriptionsThroughProxy)) {
                SettingsRowTitle(.proxyUpdates, "Update through the proxy")
                Text("For subscription addresses that cannot be reached directly.")
            }
        } header: {
            SettingsSectionHeader(.proxyUpdates)
        } footer: {
            Text("Subscription links stay in your login Keychain and never leave with a settings backup.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Advanced

    private var advanced: some View {
        Section {
            SettingsRow(
                title: "Generated Config",
                subtitle: String(localized: "Read-only, with subscription links hidden."),
                anchor: .proxyAdvanced
            ) {
                Button("Show…") { open(.config) }
            }
            SettingsRow(
                title: "Restore Default Settings",
                subtitle: String(
                    localized: "Keeps sources; strategies, routes, rules and settings start over."),
                anchor: .proxyAdvanced
            ) {
                Button("Restore…") { coordinator.restoreDefaults() }
            }
        } header: {
            SettingsSectionHeader(.proxyAdvanced)
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<ProxyGeneral, Value>) -> Binding<Value> {
        Binding(
            get: { manager.store.profile.general[keyPath: keyPath] },
            set: { value in coordinator.update { $0.general[keyPath: keyPath] = value } })
    }
}

/// Servers typed as one comma-separated line, saved once the field is left.
private struct ProxyServerListField<Label: View>: View {
    let title: LocalizedStringKey
    @Binding var servers: [String]
    @ViewBuilder let label: Label
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            TextField(title, text: $text)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 220)
                .focused($focused)
                .onSubmit(commit)
        } label: {
            label
        }
        .onAppear { text = servers.joined(separator: ", ") }
        .onChange(of: servers) { _, new in if !focused { text = new.joined(separator: ", ") } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let parsed = text.split(whereSeparator: { $0 == "," || $0 == "、" || $0.isWhitespace })
            .map(String.init).filter { !$0.isEmpty }
        if parsed != servers { servers = parsed }
        text = parsed.joined(separator: ", ")
    }
}

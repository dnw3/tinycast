import SwiftUI

/// TUN mode, the root helper that runs it, and the DNS placeholder it sets while connected.
struct ProxyTUNSection: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }
    private var helper: ProxyHelperClient { manager.helper }
    private var general: ProxyGeneral { manager.store.profile.general }

    var body: some View {
        Section {
            Toggle(isOn: helper.state == .ready ? setting(\.usesTUN) : .constant(false)) {
                SettingsRowTitle(.proxyTUN, "TUN Mode")
                Text(tunSubtitle)
            }
            .disabled(helper.state != .ready)
            SettingsRow(
                title: "TUN Helper", subtitle: helperSubtitle, subtitleLineLimit: 3, anchor: .proxyTUN
            ) {
                helperButton
            }
            Toggle(isOn: setting(\.placeholderDNS)) {
                SettingsRowTitle(.proxyTUN, "DNS Placeholder")
                Text(
                    "A LAN DNS server bypasses TUN, so a public one stands in while connected and is put back after."
                )
            }
            .disabled(helper.state != .ready || !general.usesTUN)
        } header: {
            SettingsSectionHeader(.proxyTUN)
        } footer: {
            Text(
                "The TUN helper is a resident system component; it is listed under System Settings › General › Login Items & Extensions."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .settingsEnabled(manager.store.profile.isEnabled)
        .onAppear { manager.checkHelper() }
    }

    @ViewBuilder private var helperButton: some View {
        switch helper.state {
        case .unsupported:
            EmptyView()
        case .notInstalled:
            Button("Install…") { coordinator.installHelper() }
                .disabled(helper.isInstalling)
        case .needsReinstall:
            Button("Update…") { coordinator.installHelper() }
                .disabled(helper.isInstalling)
            Button("Uninstall…") { coordinator.uninstallHelper() }
                .disabled(helper.isInstalling)
        case .ready:
            Button("Uninstall…") { coordinator.uninstallHelper() }
                .disabled(helper.isInstalling)
        }
    }

    private var tunSubtitle: String {
        switch helper.state {
        case .ready: String(localized: "Takes over every app's traffic, including terminals, games and UDP.")
        case .unsupported: String(localized: "Unavailable in this build.")
        case .notInstalled: String(localized: "Install the TUN helper below to turn it on.")
        case .needsReinstall: String(localized: "Update the TUN helper below to turn it on.")
        }
    }

    private var helperSubtitle: String {
        switch helper.state {
        case .unsupported:
            String(
                localized: "This build cannot install it, as it carries no signature the helper could check.")
        case .notInstalled:
            String(localized: "Not installed. Until it is, the proxy runs on its mixed port only.")
        case .needsReinstall:
            String(
                localized:
                    "Installed by another version of Tinycast, or not responding. Update it to use TUN.")
        case .ready where manager.isTUN:
            String(localized: "Installed · running the core as administrator")
        case .ready:
            String(localized: "Installed · runs the core as administrator while connected")
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<ProxyGeneral, Value>) -> Binding<Value> {
        Binding(
            get: { manager.store.profile.general[keyPath: keyPath] },
            set: { value in coordinator.update { $0.general[keyPath: keyPath] = value } })
    }
}

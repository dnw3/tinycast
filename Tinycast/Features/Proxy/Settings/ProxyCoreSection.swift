import SwiftUI

/// The core in use, its updates, and the ports it opens.
struct ProxyCoreSection: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    @State private var port = 0
    @FocusState private var portFocused: Bool

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        Section {
            SettingsRow(title: "mihomo", subtitle: identity, anchor: .proxyCore) {
                Button("Show Log…") { coordinator.showCoreLog() }
                Button("Restart") { manager.restart() }
                    .disabled(!manager.isRunning)
            }
            SettingsRow(
                title: "Core Updates", subtitle: updateSubtitle, subtitleLineLimit: 3, anchor: .proxyCore
            ) {
                updateControls
            }
            LabeledContent {
                HStack(spacing: Theme.Spacing.lg) {
                    Button("Copy Terminal Command") { coordinator.copyTerminalCommand() }
                    TextField("Mixed Port", value: $port, format: .number.grouping(.never))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .focused($portFocused)
                        .onSubmit(commitPort)
                }
            } label: {
                SettingsRowTitle(.proxyCore, "Mixed Port")
                Text("For tools you point at the proxy yourself.")
            }
            Toggle(isOn: allowsLAN) {
                SettingsRowTitle(.proxyCore, "Allow LAN Connections")
                Text("Lets other devices on this network use the proxy through this Mac.")
            }
        } header: {
            SettingsSectionHeader(.proxyCore)
        } footer: {
            Text("mihomo is released under the GPL-3.0; its source is at github.com/MetaCubeX/mihomo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            port = manager.store.profile.general.mixedPort
            manager.identifyActiveCore()
        }
        .onChange(of: manager.store.profile.general.mixedPort) { _, value in port = value }
        .onChange(of: portFocused) { _, focused in if !focused { commitPort() } }
    }

    private var identity: String {
        let tag = manager.coreVersion ?? manager.activeCore?.tag
        let origin: String? = manager.activeCore.map {
            $0.isBundled ? String(localized: "Bundled") : String(localized: "Downloaded")
        }
        let state = manager.isRunning ? String(localized: "Running") : String(localized: "Not running")
        guard manager.activeCore != nil || tag != nil else {
            return manager.hasBundledCore
                ? state : String(localized: "No core yet; check for updates to get one.")
        }
        return [tag, origin, state].compactMap { $0 }.joined(separator: " · ")
    }

    private var updateSubtitle: String {
        switch manager.coreUpdate {
        case .idle:
            return String(localized: "Checks GitHub only when you ask.")
        case .checking:
            return String(localized: "Checking…")
        case .upToDate:
            return String(localized: "This is the newest release.")
        case .available(let release):
            return String(
                localized:
                    "\(release.tag) is available. It is verified before it installs, and a core that cannot start is rolled back."
            )
        case .downloading(let release, _):
            return String(localized: "Downloading \(release.tag)…")
        case .installing(let release):
            return String(localized: "Verifying \(release.tag)…")
        }
    }

    @ViewBuilder private var updateControls: some View {
        if manager.activeCore?.isBundled == false, manager.hasBundledCore {
            Button("Restore Bundled Core") { coordinator.restoreBundledCore() }
        }
        switch manager.coreUpdate {
        case .idle:
            Button("Check for Updates") { manager.checkForCoreUpdate() }
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .upToDate:
            Button("Check Again") { manager.checkForCoreUpdate() }
        case .available(let release):
            Button("Update to \(release.tag)") { manager.installCoreUpdate() }
        case .downloading(_, let fraction):
            if let fraction {
                ProgressView(value: fraction).frame(width: 90)
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Cancel") { manager.cancelCoreUpdate() }
        }
    }

    private var allowsLAN: Binding<Bool> {
        Binding(
            get: { manager.store.profile.general.allowsLAN },
            set: { value in coordinator.update { $0.general.allowsLAN = value } })
    }

    private func commitPort() {
        guard (1...65535).contains(port) else {
            port = manager.store.profile.general.mixedPort
            return
        }
        coordinator.update { $0.general.mixedPort = port }
    }
}

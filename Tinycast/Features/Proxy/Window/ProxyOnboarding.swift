import SwiftUI

/// The overview before any source exists: what to do first, and what happens after.
struct ProxyOnboarding: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    @State private var link = ""

    private static let badge = 28.0

    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        ProxyPage {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Set Up the Proxy").font(.title2.weight(.semibold))
                Text("Three steps. Afterwards this page shows the connection, the exit and where traffic goes.")
                    .foregroundStyle(.secondary)
            }
            step(1, title: String(localized: "Add Nodes"), isDone: false) {
                Text(
                    "Paste the subscription link your provider gave you, or import a local node file. Tinycast reads only the nodes; groups and routing are set up here."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    // Verbatim: a literal prompt is read as Markdown, which would style the URL.
                    TextField("Subscription Link", text: $link, prompt: Text(verbatim: "https://…"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(!ProxyText.isWebURL(link.trimmingCharacters(in: .whitespaces)))
                    Button("Import File…") { coordinator.importNodeFiles() }
                }
            }
            step(2, title: String(localized: "Install the TUN Helper"), isDone: manager.helper.state == .ready) {
                Text(
                    "Taking over all of this Mac's traffic needs a system helper. macOS asks for an administrator password once; connecting and disconnecting never ask again."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if manager.helper.state != .ready {
                    Button("Install…") { coordinator.installHelper() }
                }
            }
            step(3, title: String(localized: "Connect"), isDone: false) {
                Text(
                    "Adding a subscription connects at once. The recommended routing sends mainland China and the local network direct, blocks ads, and sends the rest through the default strategy."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step<Content: View>(
        _ number: Int, title: String, isDone: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        ProxyCard {
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                ZStack {
                    Circle().fill(isDone ? Theme.Colors.success : Theme.Colors.controlSurface)
                    if isDone {
                        SymbolImage(name: "checkmark", size: Theme.Size.settingsSidebarGlyph).foregroundStyle(.white)
                    } else {
                        Text(number, format: .number).font(.headline)
                    }
                }
                .frame(width: Self.badge, height: Self.badge)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(title).font(.headline)
                    content()
                }
            }
        }
    }

    private func add() {
        let link = link.trimmingCharacters(in: .whitespaces)
        guard ProxyText.isWebURL(link) else { return }
        coordinator.addSubscription(link)
    }
}

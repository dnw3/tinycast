import SwiftUI

/// The launcher's answer to "proxy": where traffic goes now, or how to begin when nothing can.
struct ProxyLauncherCard: Equatable {
    enum Content: Equatable {
        case status(exit: String, exitBadge: String, mode: String, connection: String, connectionBadge: String)
        /// No source yet; a subscription link on the clipboard is added by ↵.
        case guide(clipboardLink: String?)
    }

    let content: Content
    let isConnected: Bool
    var mode = ProxyMode.rule
    var hasSubscriptions = false

    var primaryActionTitle: String {
        switch content {
        case .status where isConnected: String(localized: "Choose Node")
        case .status: String(localized: "Connect Proxy")
        case .guide(.some): String(localized: "Add Link")
        case .guide(nil): String(localized: "Add Subscription")
        }
    }
}

struct ProxyLauncherCardView: View {
    @Environment(\.metrics) private var metrics
    let card: ProxyLauncherCard
    let selected: Bool

    var body: some View {
        Group {
            switch card.content {
            case .status(let exit, let exitBadge, let mode, let connection, let connectionBadge):
                // The short columns hug their text, leaving a long node name room to keep its size.
                HStack(spacing: 0) {
                    LeadCardColumn(text: AttributedString(exit), badge: exitBadge)
                    separator
                    LeadCardColumn(text: AttributedString(mode), badge: String(localized: "Mode"))
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: sideColumnWidth)
                    separator
                    LeadCardColumn(text: AttributedString(connection), badge: connectionBadge)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: sideColumnWidth)
                }
            case .guide(let link):
                LeadCardColumn(
                    text: AttributedString(String(localized: "No Nodes Yet")),
                    badge: link.map {
                        String(
                            localized:
                                "Return adds the link on the clipboard: \(ProxyLauncherHint.masked($0))")
                    }
                        ?? String(
                            localized: "Add a subscription or a local file to switch nodes and routes here"))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxl)
        .leadCard(selected: selected)
        .accessibilityElement(children: .combine)
    }

    /// Room around the short columns' words, so they do not crowd the separators.
    private var sideColumnWidth: CGFloat { 150 * metrics.scale }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(width: Theme.Size.hairline)
            .padding(.vertical, metrics.spacing.sm)
    }
}

/// The card's ⌘K rows: every proxy command, so the card is a doorway rather than a dead end.
@MainActor
enum ProxyLauncherCardActions {
    static func content(card: ProxyLauncherCard, coordinator: ProxyCoordinator) -> PopoverMenuContent {
        switch card.content {
        case .status:
            var items = [
                PopoverMenuItem(
                    title: String(localized: "Choose Node"), systemImage: "network",
                    shortcut: card.isConnected ? "↵" : nil, action: { coordinator.showNodes() }),
                PopoverMenuItem(
                    title: String(localized: "Add Rule…"), systemImage: "text.badge.plus",
                    action: { coordinator.showRuleEditor() }),
                PopoverMenuItem(
                    title: String(localized: "Open Proxy Window…"), systemImage: "macwindow",
                    action: { coordinator.showWindow() })
            ]
            // Each mode keeps its own glyph so the rows line up with the ones above.
            items += ProxyMode.allCases.enumerated().map { index, mode in
                PopoverMenuItem(
                    title: mode.title, icon: .symbol(mode.symbol), startsSection: index == 0,
                    detail: card.mode == mode ? String(localized: "Current") : nil
                ) {
                    coordinator.setMode(mode)
                }
            }
            if card.isConnected {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Test Proxy Nodes"), systemImage: "speedometer",
                        startsSection: true,
                        action: { coordinator.testAllNodes() }))
            }
            if card.isConnected, card.hasSubscriptions {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Update Proxy Subscriptions"),
                        systemImage: "arrow.triangle.2.circlepath",
                        action: { coordinator.updateSubscriptions() }))
            }
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Proxy Settings…"), systemImage: "gearshape", startsSection: true
                ) {
                    coordinator.openSettings()
                })
            items.append(
                card.isConnected
                    ? PopoverMenuItem(
                        title: String(localized: "Disconnect Proxy"), systemImage: "network.slash",
                        action: { coordinator.disconnect() })
                    : PopoverMenuItem(
                        title: String(localized: "Connect Proxy"), systemImage: "network", shortcut: "↵",
                        action: { coordinator.connect() }))
            return PopoverMenuContent(header: String(localized: "Proxy"), items: items)
        case .guide(let link):
            var items: [PopoverMenuItem] = []
            if let link {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Add the Link on the Clipboard"),
                        icon: .symbol("doc.on.clipboard"),
                        shortcut: "↵", detail: ProxyLauncherHint.masked(link)
                    ) {
                        coordinator.addSubscription(link)
                    })
            }
            items += [
                PopoverMenuItem(
                    title: String(localized: "Add Subscription…"), systemImage: "link.badge.plus",
                    shortcut: link == nil ? "↵" : nil
                ) {
                    coordinator.showWindow(edit: .addSubscription(link: nil, connects: true))
                },
                PopoverMenuItem(title: String(localized: "Import Local File…"), systemImage: "doc.badge.plus")
                {
                    coordinator.showWindow(edit: .importFile)
                },
                PopoverMenuItem(
                    title: String(localized: "Proxy Settings…"), systemImage: "gearshape", startsSection: true
                ) {
                    coordinator.openSettings()
                }
            ]
            return PopoverMenuContent(header: String(localized: "Proxy"), items: items)
        }
    }
}

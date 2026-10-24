import AppKit
import SwiftUI

/// The proxy's own menu bar item, off by default: its state at a glance, and a menu to steer it.
@MainActor
final class ProxyMenuBarController: NSObject, NSMenuDelegate {
    private let status: NSStatusItem
    private let menu = NSMenu()
    private let manager: ProxyManager
    private unowned let coordinator: ProxyCoordinator

    init(manager: ProxyManager, coordinator: ProxyCoordinator) {
        self.manager = manager
        self.coordinator = coordinator
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.autosaveName = (Bundle.main.bundleIdentifier ?? "com.tinycast.app") + ".proxy"
        status.button?.imagePosition = .imageLeading
        status.button?.setAccessibilityLabel(String(localized: "Proxy"))
        menu.autoenablesItems = false
        menu.delegate = self
        status.menu = menu
        refresh(traffic: nil)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(status)
    }

    /// The icon follows the connection; the rates show beside it when the setting asks for them.
    func refresh(traffic: ProxyAPI.Traffic?) {
        guard let button = status.button else { return }
        let connected = manager.isRunning
        let image = NSImage(
            systemSymbolName: connected ? "network" : "network.slash", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !connected
        let showsSpeed = manager.store.profile.general.showsMenuBarSpeed && connected
        if showsSpeed, let traffic {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            button.title = "↓\(ProxyRate.text(traffic.down)) ↑\(ProxyRate.text(traffic.up))"
        } else {
            button.title = ""
        }
        button.toolTip = manager.statusTitle
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let profile = manager.store.profile
        menu.addItem(statusItem())
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: String(localized: "Mode")))
        for mode in ProxyMode.allCases {
            let item = ProxyMenuItem(title: mode.title) { [coordinator] in coordinator.setMode(mode) }
            item.state = manager.mode == mode ? .on : .off
            item.toolTip = mode.explanation
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: String(localized: "Strategies")))
        for strategy in profile.strategies {
            menu.addItem(strategyItem(strategy, in: profile))
        }
        menu.addItem(.separator())
        menu.addItem(ProxyMenuItem(title: String(localized: "Open Proxy Window…")) { [coordinator] in
            coordinator.showWindow()
        })
        let test = ProxyMenuItem(title: String(localized: "Test All Nodes")) { [coordinator] in
            coordinator.testAllNodes()
        }
        test.isEnabled = manager.isRunning
        menu.addItem(test)
        if profile.hasSubscriptions {
            let update = ProxyMenuItem(title: String(localized: "Update Subscriptions")) { [coordinator] in
                coordinator.updateSubscriptions()
            }
            update.isEnabled = manager.isRunning
            menu.addItem(update)
        }
        menu.addItem(ProxyMenuItem(title: String(localized: "Proxy Settings…")) { [coordinator] in
            coordinator.openSettings()
        })
    }

    private func statusItem() -> NSMenuItem {
        let wants = manager.store.wantsConnection
        let title = wants ? String(localized: "Disconnect") : String(localized: "Connect")
        let item = ProxyMenuItem(title: title) { [coordinator] in
            wants ? coordinator.disconnect() : coordinator.connect()
        }
        item.subtitle = manager.statusTitle
        item.isEnabled = manager.store.profile.isEnabled
        return item
    }

    /// A strategy shows where it exits now; a manual one opens onto its options, by region.
    private func strategyItem(_ strategy: ProxyStrategy, in profile: ProxyProfile) -> NSMenuItem {
        let item = NSMenuItem(title: strategy.name, action: nil, keyEquivalent: "")
        let reach = manager.snapshot?.reach(from: strategy.id, in: profile)
        Self.show(Self.dot(strategy.tint), on: item)
        if let node = reach?.node {
            item.subtitle = node.label
            if let label = node.delay(for: strategy.testURL).label { item.badge = NSMenuItemBadge(string: label) }
        }
        guard let group = manager.snapshot?.strategies[strategy.id] else { return item }
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let picks = strategy.kind == .select
        let nodes = manager.snapshot?.nodes ?? [:]
        for option in group.options where nodes[option] == nil {
            submenu.addItem(optionItem(option, title: ProxyPaletteRows.optionTitle(option), strategy: strategy,
                                       current: group.current, picks: picks))
        }
        let pool = group.options.compactMap { nodes[$0] }
        let grouped = Dictionary(grouping: pool, by: \.region)
        let regions: [ProxyRegion?] = ProxyRegion.allCases.map(Optional.some) + [nil]
        if !pool.isEmpty, submenu.numberOfItems > 0 { submenu.addItem(.separator()) }
        for region in regions {
            guard let members = grouped[region] else { continue }
            let regionItem = NSMenuItem(title: region?.title ?? ProxyRegion.otherTitle, action: nil, keyEquivalent: "")
            if let region { Self.show(ProxyFlagArtwork.menuImage(emoji: region.flagEmoji), on: regionItem) }
            regionItem.badge = NSMenuItemBadge(count: members.count)
            if members.contains(where: { $0.name == group.current }) { regionItem.state = .mixed }
            let regionMenu = NSMenu()
            regionMenu.autoenablesItems = false
            for node in members {
                let nodeItem = optionItem(node.name, title: node.bareName, strategy: strategy, current: group.current,
                                          picks: picks)
                if let label = node.delay(for: strategy.testURL).label { nodeItem.badge = NSMenuItemBadge(string: label) }
                regionMenu.addItem(nodeItem)
            }
            regionItem.submenu = regionMenu
            submenu.addItem(regionItem)
        }
        submenu.addItem(.separator())
        let test = ProxyMenuItem(title: String(localized: "Test Delays")) { [coordinator] in
            coordinator.testDelays(of: strategy.id)
        }
        test.isEnabled = manager.isRunning
        submenu.addItem(test)
        item.submenu = submenu
        return item
    }

    private func optionItem(
        _ option: String, title: String, strategy: ProxyStrategy, current: String?, picks: Bool
    ) -> NSMenuItem {
        let item = ProxyMenuItem(title: title) { [coordinator] in coordinator.use(option, in: strategy.id) }
        item.state = option == current ? .on : .off
        item.isEnabled = picks
        return item
    }

    /// macOS 27 hides menu images unless asked; a strategy's colour and a flag both say something.
    private static func show(_ image: NSImage, on item: NSMenuItem) {
        item.image = image
        if #available(macOS 27, *) { item.preferredImageVisibility = .visible }
    }

    private static func dot(_ tint: ProxyStrategy.Tint) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(tint.color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return image
    }
}

/// A menu item that runs a closure, so the menu needs no selector per action.
private final class ProxyMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}

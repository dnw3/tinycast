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
        for strategy in profile.strategies where strategy.soleRegion == nil {
            menu.addItem(strategyItem(strategy, in: profile))
        }
        let regional = profile.strategies.filter { $0.soleRegion != nil }
        if !regional.isEmpty {
            menu.addItem(Self.regionStrategiesItem(regional.map { strategyItem($0, in: profile) }))
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
        dress(item, as: strategy, in: profile)
        guard let group = manager.snapshot?.strategies[strategy.id] else { return item }
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let picks = strategy.kind == .select
        let nodes = manager.snapshot?.nodes ?? [:]
        var regional: [NSMenuItem] = []
        for option in group.options where nodes[option] == nil {
            let member = profile.strategies.first { $0.name == option }
            let memberItem = optionItem(
                option, title: ProxyPaletteRows.optionTitle(option), strategy: strategy,
                current: group.current, picks: picks)
            if let member { dress(memberItem, as: member, in: profile) }
            if member?.soleRegion != nil { regional.append(memberItem) } else { submenu.addItem(memberItem) }
        }
        if !regional.isEmpty { submenu.addItem(Self.regionStrategiesItem(regional)) }
        let pool = group.options.compactMap { nodes[$0] }
        let grouped = Dictionary(grouping: pool, by: \.region)
        let regions: [ProxyRegion?] = ProxyRegion.allCases.map(Optional.some) + [nil]
        if !pool.isEmpty, submenu.numberOfItems > 0 { submenu.addItem(.separator()) }
        for region in regions {
            guard let members = grouped[region] else { continue }
            let nodeItems = members.map { node in
                let nodeItem = optionItem(
                    node.name, title: node.bareName, strategy: strategy, current: group.current, picks: picks)
                if let label = node.delay(for: strategy.testURL).label {
                    nodeItem.badge = NSMenuItemBadge(string: label)
                }
                return nodeItem
            }
            // One region's nodes need no row naming their region; they sit in the strategy's menu.
            guard grouped.count > 1 else {
                for nodeItem in nodeItems { submenu.addItem(nodeItem) }
                continue
            }
            let regionItem = NSMenuItem(title: region?.title ?? ProxyRegion.otherTitle, action: nil, keyEquivalent: "")
            if let region { Self.show(ProxyFlagArtwork.menuImage(emoji: region.flagEmoji), on: regionItem) }
            regionItem.badge = NSMenuItemBadge(count: members.count)
            if members.contains(where: { $0.name == group.current }) { regionItem.state = .mixed }
            let regionMenu = NSMenu()
            regionMenu.autoenablesItems = false
            for nodeItem in nodeItems { regionMenu.addItem(nodeItem) }
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

    /// A strategy's face in a menu: its region's flag or its colour, and the node it reaches now.
    private func dress(_ item: NSMenuItem, as strategy: ProxyStrategy, in profile: ProxyProfile) {
        let region = strategy.soleRegion
        item.title = strategy.bareName
        let image = region.map { ProxyFlagArtwork.menuImage(emoji: $0.flagEmoji) } ?? Self.dot(strategy.tint)
        Self.show(image, on: item)
        guard let node = manager.snapshot?.node(reachedBy: strategy.id, in: profile) else { return }
        item.subtitle = region == nil ? node.label : ProxyNodeName(node.name).title
        if let label = node.delay(for: strategy.testURL).label { item.badge = NSMenuItemBadge(string: label) }
    }

    /// The strategies made by region under one row, as the Nodes page folds them.
    private static func regionStrategiesItem(_ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Region Strategies"), action: nil, keyEquivalent: "")
        if let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) {
            show(globe, on: item)
        }
        item.badge = NSMenuItemBadge(count: items.count)
        if items.contains(where: { $0.state == .on }) { item.state = .mixed }
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for member in items { submenu.addItem(member) }
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
        // CI builds with Xcode 26, whose SDK does not have the property yet.
        #if compiler(>=6.4)
            if #available(macOS 27, *) { item.preferredImageVisibility = .visible }
        #endif
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

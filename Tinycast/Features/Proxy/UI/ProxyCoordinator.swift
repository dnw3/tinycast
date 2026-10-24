import AppKit

/// The proxy's action surface for the launcher, its palette screens, its window and its menu bar.
@MainActor
final class ProxyCoordinator {
    let session = ProxyPaletteSession()
    let traffic: ProxyTrafficMonitor
    let connections: ProxyConnectionsMonitor
    private let manager: ProxyManager
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let appIndex: AppIndex
    /// Dialog and message-HUD presentation, and the editor handoff. Never state this type owns.
    private unowned let core: AppCore
    /// Set by Connect, so the HUD answers the connection the user asked for and no restart.
    private var announcesConnection = false
    private var reportedStatus = ProxyManager.Status.off
    private lazy var window = ProxyWindowController(core: core)
    private var menuBar: ProxyMenuBarController?

    init(
        manager: ProxyManager, palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator, appIndex: AppIndex, core: AppCore
    ) {
        self.manager = manager
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.appIndex = appIndex
        self.core = core
        traffic = ProxyTrafficMonitor(manager: manager)
        connections = ProxyConnectionsMonitor(manager: manager)
        traffic.onSample = { [weak self] sample in self?.menuBar?.refresh(traffic: sample) }
    }

    private var store: ProxyStore { manager.store }
    private var profile: ProxyProfile { manager.store.profile }

    // MARK: - Presence

    /// Commands exist while the proxy is on; only a connection or mode that would change is listed.
    func applyPresence() {
        appIndex.setCommandsVisible(Set(SettingsTab.proxy.ownedCommands), profile.isEnabled)
        appIndex.setCommandsListed([.connectProxy], !store.wantsConnection)
        appIndex.setCommandsListed([.disconnectProxy], store.wantsConnection)
        let modes: [(CommandID, ProxyMode)] = [
            (.proxyRuleMode, .rule), (.proxyGlobalMode, .global), (.proxyDirectMode, .direct)
        ]
        for (command, mode) in modes { appIndex.setCommandsListed([command], manager.mode != mode) }
        applyMenuBar()
    }

    /// The menu bar item exists only while the proxy is on and the setting asks for it.
    private func applyMenuBar() {
        let wanted = profile.isEnabled && profile.general.showsMenuBarItem
        if wanted, menuBar == nil {
            menuBar = ProxyMenuBarController(manager: manager, coordinator: self)
        } else if !wanted, let menuBar {
            menuBar.remove()
            self.menuBar = nil
        }
        traffic.setWatching(wanted && profile.general.showsMenuBarSpeed, for: .menuBar)
        menuBar?.refresh(traffic: traffic.current)
    }

    /// Runs on every change of status, notice or intent, and says what the reader should hear.
    func reflect() {
        applyPresence()
        if let notice = manager.notice {
            manager.dismissNotice()
            core.showMessage(notice.message(in: profile), tone: .danger)
        }
        let status = manager.status
        defer { reportedStatus = status }
        guard status != reportedStatus else { return }
        switch status {
        case .running where announcesConnection:
            announcesConnection = false
            core.showMessage(String(localized: "Proxy Connected"))
        case .failed(let failure):
            announcesConnection = false
            core.showMessage(failure.message(in: profile), tone: .danger)
        default:
            break
        }
    }

    // MARK: - Connection

    func connect() {
        guard profile.isEnabled else { return }
        guard !profile.sources.isEmpty else {
            showWindow(edit: .addSubscription(link: nil, connects: true))
            return
        }
        dismissPalette()
        announcesConnection = true
        manager.connect()
    }

    func disconnect() {
        dismissPalette()
        guard store.wantsConnection || manager.status != .off else { return }
        manager.disconnect()
        core.showMessage(String(localized: "Proxy Disconnected"), tone: .neutral)
    }

    /// The feature switch: turning it off also ends the connection, so nothing runs unseen.
    func setEnabled(_ enabled: Bool) {
        if !enabled, store.wantsConnection { manager.disconnect() }
        update { $0.isEnabled = enabled }
        applyPresence()
    }

    /// Saves a profile edit; a failure to save is reported, since nothing else would say so.
    @discardableResult
    func update(_ change: (inout ProxyProfile) -> Void) -> Bool {
        do {
            try manager.update(change)
            return true
        } catch {
            core.showMessage(
                String(localized: "The proxy settings could not be saved: \(error.localizedDescription)"),
                tone: .danger)
            return false
        }
    }

    // MARK: - Palette

    /// The default strategy's options, which is what picking a node means without more context.
    func showNodes() {
        session.strategyID = profile.defaultStrategy
        paletteCoordinator.togglePalette(mode: .proxyNodes)
        Task { await manager.refresh() }
    }

    func pickStrategy(forRule kind: ProxyUserRule.Kind, value: String) {
        session.rule = ProxyPaletteSession.RuleDraft(kind: kind, value: value)
        palette.push(mode: .proxyStrategies)
    }

    /// Opens on the page the user was reading, when that was a browser that will say which.
    func showRuleEditor() {
        let app = paletteCoordinator.targetApp
        let browser = ProxyBrowserPage.Browser(bundleID: app?.bundleIdentifier, name: app?.localizedName)
        session.ruleSource = nil
        paletteCoordinator.showPalette(mode: .proxyRule)
        guard let browser else { return }
        Task {
            guard let address = await ProxyBrowserPage.address(in: browser),
                palette.mode == .proxyRule, palette.query.isEmpty
            else { return }
            palette.query = ProxyUserRule.host(from: address)
            session.ruleSource = browser.name
        }
    }

    /// New rules go first, ahead of every route; a rule for the same value moves there instead.
    func addRule(_ kind: ProxyUserRule.Kind, _ value: String, to target: ProxyTarget) {
        let rule = ProxyUserRule(id: UUID(), kind: kind, value: value, target: target, isEnabled: true)
        guard
            update({ profile in
                profile.rules.removeAll { $0.kind == kind && $0.value == value }
                profile.rules.insert(rule, at: 0)
            })
        else { return }
        dismissPalette()
        core.showMessage(
            String(localized: "\(value) now goes to \(target.title(in: profile))"), tone: .success)
    }

    func openNodes(of strategy: UUID) {
        session.strategyID = strategy
        palette.push(mode: .proxyNodes)
        Task { await manager.refresh() }
    }

    func back() {
        _ = palette.pop(preservingSelection: true)
    }

    /// Shows another strategy's options in place, from the nodes screen's own menu.
    func switchNodes(to strategy: UUID) {
        session.strategyID = strategy
        palette.replace(mode: .proxyNodes)
    }

    /// Picks an option of a manual strategy, which takes effect without reloading the core.
    func use(_ option: String, in strategy: UUID) {
        guard let name = profile.strategy(strategy)?.name else { return }
        do {
            try manager.select(option, in: strategy)
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        dismissPalette()
        core.showMessage(
            String(localized: "\(name) now uses \(ProxyPaletteRows.optionTitle(option, in: manager.snapshot))"),
            tone: .success)
    }

    func toggleRoute(_ id: String) {
        update { profile in
            guard let index = profile.routes.firstIndex(where: { $0.id == id }) else { return }
            profile.routes[index].isEnabled.toggle()
        }
    }

    /// Takes effect at once on a running core, and stays chosen across restarts.
    func setMode(_ mode: ProxyMode) {
        dismissPalette()
        guard mode != manager.mode else { return }
        manager.setMode(mode)
        applyPresence()
        let message: String =
            switch mode {
            case .rule: String(localized: "Rule mode: traffic follows your routes")
            case .global:
                String(localized: "Global mode: everything goes through \(profile.strategy(profile.defaultStrategy)?.name ?? "")")
            case .direct: String(localized: "Direct mode: nothing goes through the proxy")
            }
        core.showMessage(message, tone: mode == .rule ? .success : .neutral)
    }

    func moveRoute(_ id: String, by offset: Int) {
        update { profile in
            guard let index = profile.routes.firstIndex(where: { $0.id == id }),
                profile.routes.indices.contains(index + offset)
            else { return }
            profile.routes.swapAt(index, index + offset)
        }
    }

    /// Dropped onto `anchor`, the route goes just above it; a nil anchor puts it last.
    func moveRoute(_ id: String, before anchor: String?) {
        guard id != anchor else { return }
        update { profile in
            guard let index = profile.routes.firstIndex(where: { $0.id == id }) else { return }
            let route = profile.routes.remove(at: index)
            let destination = anchor.flatMap { anchor in profile.routes.firstIndex { $0.id == anchor } }
            profile.routes.insert(route, at: destination ?? profile.routes.endIndex)
        }
    }

    func removeRoute(_ id: String) {
        guard let route = profile.routes.first(where: { $0.id == id }) else { return }
        guard update({ $0.routes.removeAll { $0.id == id } }) else { return }
        core.showMessage(String(localized: "Removed “\(route.title)”"), tone: .neutral)
    }

    /// Asks first, since the routes the user reordered or redirected go back to how they started.
    func restoreRecommendedRoutes() {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Restore the Recommended Routing?"),
                    message: String(
                        localized:
                            "The recommended routes go back to their order and targets. Routes you added stay, ahead of them."
                    ),
                    symbol: "arrow.counterclockwise", confirmTitle: String(localized: "Restore"))
            else { return }
            guard update({ $0.restoreRecommendedRoutes() }) else { return }
            core.showMessage(String(localized: "Recommended routing restored"))
        }
    }

    /// Where the running core sends a site, read from its own log of one test connection.
    func probe(_ destination: ProxyProbe.Destination) async -> Result<ProxyProbe.Outcome, ProxyProbeRunner.Failure> {
        guard let api = manager.controller else { return .failure(.unreachable) }
        do {
            return .success(
                try await ProxyProbeRunner.run(destination, api: api, port: profile.general.mixedPort))
        } catch let failure as ProxyProbeRunner.Failure {
            return .failure(failure)
        } catch {
            return .failure(.unreachable)
        }
    }

    func testNode(_ name: String) {
        guard manager.isRunning else {
            core.showMessage(String(localized: "Connect the proxy to test its nodes"), tone: .neutral)
            return
        }
        core.showProgress(String(localized: "Testing “\(name)”…"))
        Task {
            await manager.testNode(name)
            core.hideProgress()
        }
    }

    func copyNodeName(_ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        core.showMessage(String(localized: "Name copied"))
    }

    func route(_ id: String, to target: ProxyTarget) {
        do {
            try manager.route(id, to: target)
            let title =
                id == ProxyRoute.finalID ? ProxyRoute.finalTitle : profile.routes.first { $0.id == id }?.title
            core.showMessage(
                String(localized: "\(title ?? id) now uses \(target.title(in: profile))"), tone: .success)
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    func testDelays(of strategy: UUID) {
        guard manager.isRunning else { return }
        let name = profile.strategy(strategy)?.name ?? ""
        core.showProgress(String(localized: "Testing “\(name)”…"))
        Task {
            await manager.testDelays(of: strategy)
            core.hideProgress()
        }
    }

    func testAllNodes() {
        dismissPalette()
        guard manager.isRunning else {
            core.showMessage(String(localized: "Connect the proxy to test its nodes"), tone: .neutral)
            return
        }
        let task = Task { await manager.testSources() }
        core.showProgress(String(localized: "Testing every node…"), onCancel: { task.cancel() })
        Task {
            await task.value
            core.hideProgress()
            core.showMessage(String(localized: "Node delays updated"))
        }
    }

    func updateSubscriptions() {
        dismissPalette()
        guard profile.hasSubscriptions else {
            core.showMessage(String(localized: "No subscriptions to update"), tone: .neutral)
            return
        }
        guard manager.isRunning else {
            core.showMessage(String(localized: "Connect the proxy to update subscriptions"), tone: .neutral)
            return
        }
        core.showProgress(String(localized: "Updating subscriptions…"))
        Task {
            await manager.updateSources()
            core.hideProgress()
            if manager.notice == nil { core.showMessage(String(localized: "Subscriptions updated")) }
        }
    }

    func updateRuleSets() {
        Task {
            guard await manager.updateRuleSets() else { return }
            core.showMessage(String(localized: "Rule sets updated"))
        }
    }

    private func dismissPalette() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    // MARK: - Launcher card

    /// The card the launcher leads with when the query asks for the proxy; nil otherwise.
    func launcherCard(for query: String) -> ProxyLauncherCard? {
        guard profile.isEnabled, ProxyLauncherHint.asksForProxy(query) else { return nil }
        guard !profile.sources.isEmpty else {
            let link = ProxyLauncherHint.subscriptionLink(in: NSPasteboard.general.string(forType: .string))
            return ProxyLauncherCard(content: .guide(clipboardLink: link), isConnected: false)
        }
        let primary = profile.strategy(profile.defaultStrategy)
        var exit = primary?.name ?? ""
        var exitBadge = String(localized: "Default Strategy")
        if manager.isRunning, manager.mode != .direct,
            let reached = manager.snapshot?.node(reachedBy: profile.defaultStrategy, in: profile)
        {
            exit = reached.label
            exitBadge = [primary?.name, reached.delay(for: primary?.testURL).label].compactMap(\.self)
                .joined(separator: " · ")
        } else if manager.mode == .direct {
            exit = String(localized: "Direct")
        }
        let connection = manager.isRunning ? String(localized: "Connected") : manager.statusTitle
        return ProxyLauncherCard(
            content: .status(
                exit: exit, exitBadge: exitBadge, mode: manager.mode.title,
                connection: connection,
                connectionBadge: manager.isTUN ? "TUN" : String(localized: "Port \(String(profile.general.mixedPort))")),
            isConnected: manager.isRunning, mode: manager.mode, hasSubscriptions: profile.hasSubscriptions)
    }

    func activate(_ card: ProxyLauncherCard) {
        switch card.content {
        case .status where card.isConnected: showNodes()
        case .status: connect()
        case .guide(let link?): addSubscription(link)
        case .guide(nil): showWindow(edit: .addSubscription(link: nil, connects: true))
        }
    }

    /// A first subscription from the clipboard, named for its host and connected at once.
    func addSubscription(_ link: String) {
        let host = URLComponents(string: link)?.host ?? String(localized: "Subscription")
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let failure = saveSource(.subscription(id: UUID(), name: name), link: link, connects: true) {
            core.showMessage(failure, tone: .danger)
        }
    }

    // MARK: - Window and Settings

    /// Opens the proxy window, on `page` if given, with `edit` open over it.
    func showWindow(page: ProxyWindowPage? = nil, edit: ProxyEditRequest.Kind? = nil) {
        dismissPalette()
        window.show(page: page, edit: edit)
    }

    func focusExistingWindow() -> Bool {
        window.focusExisting()
    }

    /// Reads traffic or connections only while a page that shows them is on screen.
    func windowShows(_ page: ProxyWindowPage?) {
        traffic.setWatching(page == .overview, for: .window)
        if page == .activity { connections.start() } else { connections.stop() }
        if page != nil { Task { await manager.refresh() } }
    }

    func openSettings(revealing anchor: SettingsAnchor? = nil) {
        dismissPalette()
        settingsCoordinator.showSettings(tab: .proxy, revealing: anchor.map(SettingsTarget.section))
    }

    /// Stores the link before the profile, so the reload the edit starts already fetches from it.
    func saveSource(_ source: ProxySource, link: String?, connects: Bool) -> String? {
        let previous = profile.sources.first { $0.id == source.id }
        if let link, link != store.subscriptionURL(for: source.id) {
            do {
                try store.setSubscriptionURL(link, for: source.id)
            } catch {
                return String(localized: "The link could not be saved to your login Keychain.")
            }
            if let previous { manager.discardCachedNodes(of: previous) }
        }
        do {
            try manager.update { profile in
                if let index = profile.sources.firstIndex(where: { $0.id == source.id }) {
                    profile.sources[index] = source
                } else {
                    profile.sources.append(source)
                }
            }
        } catch {
            if previous == nil { try? store.removeSubscriptionURL(for: source.id) }
            return String(localized: "The proxy settings could not be saved: \(error.localizedDescription)")
        }
        if previous == nil, connects { connect() }
        return nil
    }

    /// Hung from the proxy window, so it shows wherever that window is, a full-screen space too.
    func importNodeFiles() {
        Task {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.prompt = String(localized: "Add")
            panel.message = String(
                localized: "Choose Clash node files, or text files with one share link per line.")
            guard await window.runSheet(panel) == .OK else { return }
            for url in panel.urls {
                let outline = await ProxyNodeFileReader.outline(of: url)
                addFileSource(url, outline: outline)
            }
        }
    }

    /// Adds a node file where it lives; the core is given a fresh copy of it each time it starts.
    func addFileSource(_ url: URL, outline: ProxyNodeFileOutline? = nil) {
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        guard !profile.sources.contains(where: { $0.kind == .file(path: path) }) else {
            core.showMessage(
                String(localized: "“\(url.lastPathComponent)” is already a source"), tone: .neutral)
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        guard update({ $0.sources.append(.file(id: UUID(), name: name, path: path)) }), let outline else {
            return
        }
        core.showMessage(outline.importMessage(name: name), tone: outline.nodes > 0 ? .success : .danger)
    }

    func reportNodeFileFailure(_ error: any Error) {
        core.showMessage(
            String(localized: "The node file could not be created: \(error.localizedDescription)"),
            tone: .danger)
    }

    /// Asks before a source goes, naming the strategies that pick from it alone.
    func deleteSource(_ id: UUID) {
        guard let source = profile.sources.first(where: { $0.id == id }) else { return }
        let dependents = profile.strategies.filter { $0.pool?.sources?.contains(id) == true }.map(\.name)
        let message =
            dependents.isEmpty
            ? String(localized: "Its nodes leave the node pool.")
            : String(
                localized:
                    "Its nodes leave the node pool, including those \(dependents.formatted(.list(type: .and))) picks from."
            )
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Delete “\(source.name)”?"), message: message, symbol: "trash",
                    confirmTitle: String(localized: "Delete")),
                profile.sources.contains(where: { $0.id == id })
            else { return }
            guard
                update({ profile in
                    profile.sources.removeAll { $0.id == id }
                    for index in profile.strategies.indices {
                        profile.strategies[index].pool?.sources?.removeAll { $0 == id }
                    }
                })
            else { return }
            try? store.removeSubscriptionURL(for: id)
            manager.discardCachedNodes(of: source)
        }
    }

    /// Repoints everything that used the strategy at the default one, so nothing is left dangling.
    func deleteStrategy(_ id: UUID) {
        guard id != profile.defaultStrategy, let strategy = profile.strategy(id) else { return }
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Delete “\(strategy.name)”?"),
                    message: String(
                        localized: "Routes and rules that use it switch to the default strategy."),
                    symbol: "trash", confirmTitle: String(localized: "Delete")),
                profile.strategy(id) != nil
            else { return }
            update { profile in
                let fallback = ProxyTarget.strategy(profile.defaultStrategy)
                profile.strategies.removeAll { $0.id == id }
                for index in profile.strategies.indices {
                    profile.strategies[index].members.removeAll { $0 == .strategy(id) }
                }
                for index in profile.routes.indices where profile.routes[index].target == .strategy(id) {
                    profile.routes[index].target = fallback
                }
                for index in profile.rules.indices where profile.rules[index].target == .strategy(id) {
                    profile.rules[index].target = fallback
                }
                if profile.finalTarget == .strategy(id) { profile.finalTarget = fallback }
            }
        }
    }

    /// Gives each later source that repeats an earlier name a prefix of its own name.
    func prefixDuplicates() {
        guard let snapshot = manager.snapshot, !snapshot.duplicates.isEmpty else { return }
        update { profile in
            var seen: Set<String> = []
            for index in profile.sources.indices where profile.sources[index].isEnabled {
                let source = profile.sources[index]
                var names = snapshot.sources[source.id]?.nodes ?? []
                if source.prefix.isEmpty, names.contains(where: seen.contains) {
                    let prefix = source.name + " · "
                    profile.sources[index].prefix = prefix
                    names = names.map { prefix + $0 }
                }
                seen.formUnion(names)
            }
        }
    }

    /// Strategies, routes, rules and settings back to the start; sources and their links stay.
    func restoreDefaults() {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Restore Default Proxy Settings?"),
                    message: String(
                        localized:
                            "Subscriptions and local files stay. Strategies, routes, rules and settings start over."
                    ),
                    symbol: "arrow.counterclockwise", confirmTitle: String(localized: "Restore"))
            else { return }
            update { profile in
                let starter = ProxyProfile.starter(
                    defaultName: String(localized: "Default Proxy"),
                    fastestName: String(localized: "Fastest"),
                    newID: UUID.init)
                profile = ProxyProfile(
                    isEnabled: profile.isEnabled, sources: profile.sources, strategies: starter.strategies,
                    defaultStrategy: starter.defaultStrategy, routes: starter.routes,
                    finalTarget: starter.finalTarget, rules: [], general: ProxyGeneral())
            }
        }
    }

    func restoreBundledCore() {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Restore the Bundled Core?"),
                    message: String(
                        localized: "Every downloaded core is deleted, and the one Tinycast shipped with runs."
                    ),
                    symbol: "arrow.uturn.backward", confirmTitle: String(localized: "Restore"))
            else { return }
            manager.restoreBundledCore()
        }
    }

    // MARK: - TUN helper

    /// Explained first, since the next thing the user sees is macOS asking for an administrator.
    func installHelper() {
        Task {
            let reinstalling = manager.helper.state == .needsReinstall
            guard
                await core.confirm(
                    title: reinstalling
                        ? String(localized: "Update the TUN Helper?")
                        : String(localized: "Install the TUN Helper?"),
                    message: String(
                        localized:
                            "TUN needs a resident system component to take over this Mac's traffic. macOS asks for an administrator password once; you can uninstall it in Settings › Proxy."
                    ),
                    symbol: "lock.shield", confirmTitle: String(localized: "Install"), tone: .neutral,
                    confirmRole: .standard)
            else { return }
            let outcome = await manager.installHelper(
                prompt: String(localized: "Tinycast wants to install its TUN helper."))
            report(outcome, done: String(localized: "TUN helper installed"))
        }
    }

    func uninstallHelper() {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Uninstall the TUN Helper?"),
                    message: String(
                        localized:
                            "The proxy keeps working on its mixed port only. DNS settings the helper changed are put back."
                    ),
                    symbol: "lock.shield", confirmTitle: String(localized: "Uninstall"))
            else { return }
            let outcome = await manager.uninstallHelper(
                prompt: String(localized: "Tinycast wants to remove its TUN helper."))
            report(outcome, done: String(localized: "TUN helper uninstalled"))
        }
    }

    private func report(_ outcome: ProxyHelperInstaller.Outcome, done: String) {
        switch outcome {
        case .done: core.showMessage(done)
        case .cancelled: break
        case .failed(let reason): core.showMessage(reason, tone: .danger)
        }
    }

    func copyTerminalCommand() {
        let port = profile.general.mixedPort
        let command =
            "export https_proxy=http://127.0.0.1:\(port) http_proxy=http://127.0.0.1:\(port) "
            + "all_proxy=socks5://127.0.0.1:\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        core.showMessage(String(localized: "Terminal command copied"))
    }

    /// The log of whichever core ran last: the user-level one's, or the TUN core's recorded copy.
    func showCoreLog() {
        let logs = ["core.log", ProxyManager.tunLogName].map { store.coreDirectory.appending(path: $0) }
        let dated = logs.compactMap { log in
            (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map {
                (log, $0)
            }
        }
        guard let latest = dated.max(by: { $0.1 < $1.1 })?.0 else {
            core.showMessage(String(localized: "The core has not written a log yet"), tone: .neutral)
            return
        }
        NSWorkspace.shared.open(latest)
    }
}

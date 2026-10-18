import SwiftUI

enum CleanupRow: Identifiable, Hashable {
    case overview
    case access
    case group(CleanupTargetID)
    case item(String)

    var id: String {
        switch self {
        case .overview: return "overview"
        case .access: return "access"
        case .group(let id): return "group:" + id.rawValue
        case .item(let path): return "item:" + path
        }
    }
}

/// Both cleanup modes: the categorized list, and one group's items after a drill-in.
struct CleanupScreen: PaletteScreen {
    enum Scope {
        case root
        case group
    }

    let scope: Scope
    let session: CleanupSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var coordinator: CleanupCoordinator { core.cleanupCoordinator }
    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    private var query: String { vm.query.trimmingCharacters(in: .whitespaces) }

    var rows: [CleanupRow] {
        switch scope {
        case .root:
            let groups = session.groups.filter { group in
                query.isEmpty || group.target.id.title.localizedCaseInsensitiveContains(query)
                    || group.items.contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            let header: [CleanupRow] = query.isEmpty ? [.overview] + (session.hasFullDiskAccess ? [] : [.access]) : []
            return header + groups.map { .group($0.id) }
        case .group:
            return session.focusedItems.filter { item in
                query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
                    || item.path.localizedCaseInsensitiveContains(query)
            }
            .map { .item($0.path) }
        }
    }

    /// Back from a group, the parent lands on the row that was opened.
    var landingSelection: Int {
        guard scope == .root, let focused = session.focusedGroupID else { return 0 }
        return rows.firstIndex(of: .group(focused)) ?? 0
    }

    private func row(at selection: Int) -> CleanupRow? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func group(_ id: CleanupTargetID) -> CleanupGroup? { session.plan.group(id) }

    private func isDrillable(_ group: CleanupGroup) -> Bool {
        group.items.count > 1 || group.target.isGeneric
    }

    // MARK: - Footer

    var primaryActionTitle: String {
        if row(at: vm.selection) == .access { return String(localized: "Open Privacy Settings") }
        if session.isCleaning { return String(localized: "Cleaning…") }
        let bytes = session.selectedBytes
        return bytes > 0
            ? String(localized: "Clean Up \(CleanupCoordinator.format(bytes))") : String(localized: "Clean Up")
    }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        if row(at: selection) == .access { return true }
        return !session.isCleaning && !session.effectiveSelection.isEmpty
    }

    func isPrimaryActionDestructive(at selection: Int) -> Bool {
        row(at: selection) != .access
    }

    func activate(at selection: Int) {
        if row(at: selection) == .access {
            coordinator.openFullDiskAccessSettings()
            return
        }
        coordinator.performCleanup()
    }

    /// ⌘↵ checks the highlighted row, a group toggling every item it can.
    func secondary(at selection: Int) -> Bool {
        switch row(at: selection) {
        case .group(let id):
            guard let group = group(id), group.target.isSelectable else { return false }
            session.toggle(group)
            return true
        case .item(let path):
            guard let item = session.plan.item(path) else { return false }
            session.toggle(item)
            return true
        case .overview, .access, nil:
            return false
        }
    }

    func navigateHorizontally(_ delta: Int, at selection: Int) -> Bool {
        switch scope {
        case .root:
            guard delta > 0, case .group(let id) = row(at: selection), let group = group(id), isDrillable(group)
            else { return false }
            coordinator.openGroup(id)
            return true
        case .group:
            guard delta < 0 else { return false }
            coordinator.closeGroup()
            return true
        }
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .showDetails:
            return navigateHorizontally(1, at: selection)
        case .restart:
            coordinator.rescan()
            return true
        case .settings:
            coordinator.openSettings()
            return true
        case .showInFinder:
            guard let path = path(at: selection) else { return false }
            coordinator.showInFinder(path)
            return true
        case .copyPath:
            guard let path = path(at: selection) else { return false }
            coordinator.copyPath(path)
            return true
        default:
            return false
        }
    }

    /// One item's path, or the folder a multi-item group's first item sits in.
    private func path(at selection: Int) -> String? {
        switch row(at: selection) {
        case .item(let path): return path.hasPrefix("/") ? path : nil
        case .group(let id):
            guard let first = group(id)?.items.first, first.isOnDisk else { return nil }
            return group(id)?.items.count == 1 ? first.path : (first.path as NSString).deletingLastPathComponent
        case .overview, .access, nil: return nil
        }
    }

    func hasActions(at selection: Int) -> Bool {
        switch row(at: selection) {
        case .group, .item: return true
        case .overview, .access, nil: return false
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        CleanupActionsMenu.content(
            row: row(at: selection), path: path(at: selection), session: session,
            coordinator: coordinator)
    }

    // MARK: - Body

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        let selected = rows.indices.contains(selection) ? rows[selection] : nil
        HStack(spacing: 0) {
            Group {
                if rows.isEmpty {
                    EmptyResults(
                        text: query.isEmpty ? String(localized: "Nothing to clean here") : String(localized: "No matches"))
                } else {
                    CleanupList(
                        rows: rows, scope: scope, session: session, selectedID: selected?.id, scroll: scroll,
                        appName: coordinator.appName,
                        onSelect: { row in vm.selection = rows.firstIndex(of: row) ?? 0 },
                        onToggle: { row in
                            if let index = rows.firstIndex(of: row) { _ = secondary(at: index) }
                        },
                        onOpen: { row in
                            guard let index = rows.firstIndex(of: row) else { return }
                            vm.selection = index
                            if !navigateHorizontally(1, at: index) { _ = secondary(at: index) }
                        },
                        onActions: { row in
                            if let index = rows.firstIndex(of: row) { vm.selection = index }
                            openActions()
                        })
                }
            }
            .frame(width: metrics.size.clipboardListWidth)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: Theme.Size.hairline)
            CleanupDetail(row: selected, session: session, appName: coordinator.appName, history: core.cleanupSchedule)
        }
    }
}

@MainActor
enum CleanupActionsMenu {
    static func content(
        row: CleanupRow?, path: String?, session: CleanupSession,
        coordinator: CleanupCoordinator
    ) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        var header = String(localized: "Clean Up")
        if !session.effectiveSelection.isEmpty, !session.isCleaning {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Clean Up Selected"), systemImage: "trash", shortcut: "↵",
                    isDestructive: true
                ) { coordinator.performCleanup() })
        }
        switch row {
        case .group(let id):
            guard let group = session.plan.group(id) else { return nil }
            header = id.title
            if group.target.isSelectable, session.isAvailable(group) {
                let on = session.state(of: group) == .on
                items.append(
                    PopoverMenuItem(
                        title: on ? String(localized: "Unselect") : String(localized: "Select"),
                        systemImage: on ? "square" : "checkmark.square", startsSection: true, shortcut: "⌘↵"
                    ) { session.toggle(group) })
            }
            if group.items.count > 1 || group.target.isGeneric {
                items.append(
                    PopoverMenuItem(title: String(localized: "Show Items"), systemImage: "list.bullet", shortcut: "⌘I") {
                        coordinator.openGroup(id)
                    })
            }
            if id == .trash {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Empty Trash…"), systemImage: "trash.slash", startsSection: true,
                        isDestructive: true
                    ) { coordinator.emptyTrash() })
            }
        case .item(let itemPath):
            guard let item = session.plan.item(itemPath) else { return nil }
            header = item.name
            if case .running(let owner) = session.lock(item) {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Quit \(coordinator.appName(owner))"), systemImage: "xmark.circle",
                        startsSection: true
                    ) { coordinator.quitOwner(of: item) })
            } else if item.target.isSelectable, session.lock(item) == nil {
                let on = session.isChecked(item)
                items.append(
                    PopoverMenuItem(
                        title: on ? String(localized: "Unselect") : String(localized: "Select"),
                        systemImage: on ? "square" : "checkmark.square", startsSection: true, shortcut: "⌘↵"
                    ) { session.toggle(item) })
            }
        case .overview, .access, nil:
            break
        }
        if let excludable = excludablePath(row: row, session: session) {
            items.append(
                PopoverMenuItem(title: String(localized: "Don’t Scan This"), systemImage: "eye.slash") {
                    coordinator.exclude(excludable)
                })
        }
        if let path {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", startsSection: true,
                    shortcut: "⌘F"
                ) { coordinator.showInFinder(path) })
            items.append(
                PopoverMenuItem(title: String(localized: "Copy Path"), systemImage: "doc.on.clipboard", shortcut: "⌃⌘C") {
                    coordinator.copyPath(path)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Select Everything Safe"), systemImage: "checkmark.circle", startsSection: true
            ) { session.selectSafe() })
        items.append(
            PopoverMenuItem(title: String(localized: "Deselect All"), systemImage: "circle") { session.deselectAll() })
        items.append(
            PopoverMenuItem(title: String(localized: "Scan Again"), systemImage: "arrow.clockwise", shortcut: "⌘R") {
                coordinator.rescan()
            })
        return PopoverMenuContent(header: header, items: items)
    }

    /// One folder only: excluding a many-item group's parent would hide every sibling target too.
    private static func excludablePath(row: CleanupRow?, session: CleanupSession) -> String? {
        switch row {
        case .item(let path): return path
        case .group(let id):
            guard let items = session.plan.group(id)?.items, items.count == 1 else { return nil }
            return items[0].path
        case .overview, .access, nil: return nil
        }
    }
}

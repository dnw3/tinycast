import SwiftUI

/// One folder's contents, largest first once measured; each drill-in is its own palette frame.
struct DiskUsageScreen: PaletteScreen {
    let session: DiskUsageSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var coordinator: DiskUsageCoordinator { core.diskUsageCoordinator }
    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    private var level: DiskUsageLevel? { session.level(at: coordinator.depth) }
    private var query: String { vm.query.trimmingCharacters(in: .whitespaces) }

    var rows: [DiskUsageEntry] {
        let entries = level?.entries ?? []
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func entry(at selection: Int) -> DiskUsageEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    var primaryActionTitle: String {
        switch entry(at: vm.selection)?.kind {
        case .guarded: String(localized: "Open Privacy Settings")
        case .file: String(localized: "Show in Finder")
        default: String(localized: "Open")
        }
    }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        return entry.canOpen || entry.kind == .guarded || entry.kind == .file
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        switch entry.kind {
        case .folder: coordinator.open(entry)
        case .guarded: coordinator.openFullDiskAccessSettings()
        case .file: coordinator.showInFinder(entry.path)
        case .unattributed: break
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    func navigateHorizontally(_ delta: Int, at selection: Int) -> Bool {
        if delta < 0 {
            guard coordinator.depth > 0 else { return false }
            coordinator.back()
            return true
        }
        guard let entry = entry(at: selection), entry.canOpen else { return false }
        coordinator.open(entry)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch shortcut {
        case .showDetails: return navigateHorizontally(1, at: selection)
        case .showInFinder:
            guard entry.kind != .unattributed else { return false }
            coordinator.showInFinder(entry.path)
            return true
        case .copyPath:
            guard entry.kind != .unattributed else { return false }
            coordinator.copyPath(entry.path)
            return true
        case .delete:
            coordinator.trash(entry)
            return true
        default:
            return false
        }
    }

    func hasActions(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        return entry.kind != .unattributed
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection), entry.kind != .unattributed else { return nil }
        var items: [PopoverMenuItem] = []
        if entry.canOpen {
            items.append(
                PopoverMenuItem(title: String(localized: "Open"), systemImage: "chevron.right", shortcut: "→") {
                    coordinator.open(entry)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Show in Finder"), systemImage: "folder", startsSection: !items.isEmpty,
                shortcut: "⌘F"
            ) { coordinator.showInFinder(entry.path) })
        items.append(
            PopoverMenuItem(title: String(localized: "Copy Path"), systemImage: "doc.on.clipboard", shortcut: "⌃⌘C") {
                coordinator.copyPath(entry.path)
            })
        if DiskUsagePolicy.canTrash(entry.path, home: NSHomeDirectory()), entry.kind != .guarded {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move to Trash…"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) { coordinator.trash(entry) })
        }
        return PopoverMenuContent(header: entry.name, items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        let selected = rows.indices.contains(selection) ? rows[selection] : nil
        HStack(spacing: 0) {
            Group {
                if level?.listing == .loading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if level?.listing == .unreadable {
                    EmptyResults(
                        text: String(localized: "Can’t read this folder"),
                        detail: session.hasFullDiskAccess
                            ? nil : String(localized: "Tinycast may need Full Disk Access to read it."),
                        systemImage: "lock")
                } else if rows.isEmpty {
                    EmptyResults(
                        text: query.isEmpty ? String(localized: "This folder is empty") : String(localized: "No matches"),
                        systemImage: "folder")
                } else {
                    DiskUsageList(
                        level: level, rows: rows, selectedID: selected?.id, scroll: scroll,
                        onSelect: { entry in vm.selection = rows.firstIndex(of: entry) ?? 0 },
                        onOpen: { entry in
                            guard let index = rows.firstIndex(of: entry) else { return }
                            vm.selection = index
                            activate(at: index)
                        },
                        onActions: { entry in
                            if let index = rows.firstIndex(of: entry) { vm.selection = index }
                            openActions()
                        })
                }
            }
            .frame(width: metrics.size.clipboardListWidth)
            .modifier(CleanupSelectionAnchor(ids: rows.map(\.id), query: query, vm: vm))
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: Theme.Size.hairline)
            DiskUsageDetail(level: level, entry: selected)
        }
    }
}

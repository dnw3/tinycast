import SwiftUI

struct CaptureHistoryScreen: PaletteScreen {
    let coordinator: CaptureCoordinator
    let vm: PaletteState
    let openActions: () -> Void
    private var query: String { vm.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var rows: [CaptureHistoryEntry] {
        let query = query, text = coordinator.historySearchText
        guard !query.isEmpty else { return coordinator.historyEntries }
        return coordinator.historyEntries.filter {
            (text[$0.id] ?? $0.title).localizedCaseInsensitiveContains(query)
        }
    }
    var primaryActionTitle: String {
        let rows = rows
        return rows.indices.contains(vm.selection) && rows[vm.selection].animationDuration != nil
            ? String(localized: "Preview GIF") : String(localized: "Open in Editor")
    }

    private func entry(at selection: Int) -> CaptureHistoryEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        coordinator.openHistory(entry)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.openHistory(entry, action: "copy")
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch shortcut {
        case .delete: coordinator.deleteHistory(entry)
        case .quickLook: coordinator.openHistory(entry, action: "preview")
        case .copyFile: coordinator.openHistory(entry, action: "copyFile")
        default: return false
        }
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        var items: [PopoverMenuItem] = [
            .init(
                title: entry.animationDuration == nil
                    ? String(localized: "Open in Editor") : String(localized: "Preview GIF"),
                systemImage: "pencil", shortcut: "↵"
            ) {
                coordinator.openHistory(entry)
            },
            .init(title: String(localized: "Copy"), systemImage: "doc.on.doc", shortcut: "⌘↵") {
                coordinator.openHistory(entry, action: "copy")
            },
            .init(title: String(localized: "Quick Preview"), systemImage: "eye", shortcut: "⌘Y") {
                coordinator.openHistory(entry, action: "preview")
            },
            .init(title: String(localized: "Share…"), systemImage: "square.and.arrow.up") {
                coordinator.openHistory(entry, action: "share")
            },
            .init(title: String(localized: "Show in Finder"), systemImage: "folder") {
                coordinator.revealHistory(entry)
            },
            .init(
                title: String(localized: "Delete"), systemImage: "trash", shortcut: "⌃X",
                isDestructive: true
            ) {
                coordinator.deleteHistory(entry)
            }
        ]
        if entry.videoDuration == nil, entry.animationDuration == nil {
            items.insert(
                .init(title: String(localized: "Copy File"), systemImage: "doc", shortcut: "⇧⌘C") {
                    coordinator.openHistory(entry, action: "copyFile")
                }, at: 2)
            items.insert(
                .init(title: String(localized: "Pin Image"), systemImage: "pin") {
                    coordinator.openHistory(entry, action: "pin")
                }, at: 2)
        }
        if let destination = coordinator.settings.uploadDestination,
            destination.kind != .imgbb || entry.videoDuration == nil
        {
            items.insert(
                .init(
                    title: String(localized: "Upload to \(destination.title) and Copy Link"),
                    systemImage: "icloud.and.arrow.up"
                ) {
                    coordinator.openHistory(entry, action: "upload")
                }, at: 4)
        }
        return PopoverMenuContent(items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            CaptureHistoryList(
                rows: rows, searching: !query.isEmpty, directory: coordinator.repository.history,
                selection: selection, scroll: scroll,
                onSelect: { vm.selection = $0 }, onActivate: { activate(at: $0) },
                onActions: {
                    vm.selection = $0; openActions()
                }, onDrag: { CaptureFileProvider.make($0, repository: coordinator.repository) }))
    }
}

import SwiftUI

struct CaptureHistoryScreen: PaletteScreen {
    let coordinator: CaptureCoordinator
    let vm: PaletteState
    let openActions: () -> Void
    var rows: [CaptureHistoryEntry] {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return coordinator.historyEntries.filter {
            query.isEmpty
                || ($0.title + " " + $0.date.formatted() + " " + $0.subtitle)
                    .localizedCaseInsensitiveContains(query)
        }
    }
    var primaryActionTitle: String {
        rows.indices.contains(vm.selection) && rows[vm.selection].animationDuration != nil ? "Preview GIF" : "Open in Editor"
    }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        coordinator.openHistory(rows[selection])
    }

    func secondary(at selection: Int) -> Bool {
        guard rows.indices.contains(selection) else { return false }
        coordinator.openHistory(rows[selection], action: "copy")
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        let entry = rows[selection]
        var items: [PopoverMenuItem] = [
            .init(title: entry.animationDuration == nil ? "Open in Editor" : "Preview GIF",
                systemImage: "pencil", shortcut: "↵") {
                coordinator.openHistory(entry)
            },
            .init(title: "Copy", systemImage: "doc.on.doc") {
                coordinator.openHistory(entry, action: "copy")
            },
            .init(title: "Quick Preview", systemImage: "eye") {
                coordinator.openHistory(entry, action: "preview")
            },
            .init(title: "Share…", systemImage: "square.and.arrow.up") {
                coordinator.openHistory(entry, action: "share")
            },
            .init(title: "Show in Finder", systemImage: "folder") { coordinator.revealHistory(entry) },
            .init(title: "Delete", systemImage: "trash", isDestructive: true) {
                coordinator.deleteHistory(entry)
            }
        ]
        if entry.videoDuration == nil, entry.animationDuration == nil {
            items.insert(.init(title: "Copy File", systemImage: "doc") {
                coordinator.openHistory(entry, action: "copyFile")
            }, at: 2)
            items.insert(.init(title: "Pin Image", systemImage: "pin") {
                coordinator.openHistory(entry, action: "pin")
            }, at: 2)
        }
        if let destination = coordinator.settings.uploadDestination,
            destination.kind != .imgbb || entry.videoDuration == nil {
            items.insert(.init(title: "Upload to \(destination.title) and Copy Link", systemImage: "icloud.and.arrow.up") {
                coordinator.openHistory(entry, action: "upload")
            }, at: 4)
        }
        return PopoverMenuContent(items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            CaptureHistoryList(
                rows: rows, directory: coordinator.repository.history, selection: selection, scroll: scroll,
                onSelect: { vm.selection = $0 }, onActivate: { activate(at: $0) },
                onActions: {
                    vm.selection = $0; openActions()
                }, onDrag: { CaptureFileProvider.make($0, repository: coordinator.repository) }))
    }
}

import AppKit

/// The analyzer's actions; a level is one palette frame, so ← and Esc step back out of it.
@MainActor
final class DiskUsageCoordinator {
    private let session: DiskUsageSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore

    init(session: DiskUsageSession, palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func show() {
        paletteCoordinator.togglePalette(mode: .diskUsage)
    }

    func load() {
        session.openRoot()
    }

    /// How deep the palette is in the analyzer, counted from its frames.
    var depth: Int { palette.backStack.count { $0.mode == .diskUsage } }

    func open(_ entry: DiskUsageEntry) {
        guard entry.canOpen else { return }
        session.enter(entry, from: depth)
        palette.push(mode: .diskUsage)
    }

    func back() {
        _ = palette.pop(preservingSelection: true)
    }

    func showInFinder(_ path: String) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(URL(fileURLWithPath: path))
    }

    func copyPath(_ path: String) {
        Paster.copyPlainText(path)
        core.showMessage(String(localized: "Copied path"))
    }

    func openFullDiskAccessSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Permissions.openFullDiskAccessSettings()
    }

    /// Moves one chosen item to the Trash after asking; only inside home and outside Library.
    func trash(_ entry: DiskUsageEntry) {
        guard entry.kind == .folder || entry.kind == .file,
            DiskUsagePolicy.canTrash(entry.path, home: NSHomeDirectory())
        else {
            core.showMessage(String(localized: "Tinycast doesn’t move this to the Trash"), tone: .danger)
            return
        }
        let size = entry.bytes.map(CleanupCoordinator.format) ?? ""
        Task {
            guard await core.confirm(
                title: String(localized: "Move “\(entry.name)” to the Trash?"),
                message: size.isEmpty
                    ? String(localized: "You can put it back from the Trash.")
                    : String(localized: "\(size). You can put it back from the Trash."),
                symbol: "trash", confirmTitle: String(localized: "Move to Trash"))
            else { return }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: entry.path), resultingItemURL: nil)
                session.remove(entry.path)
                core.showMessage(String(localized: "Moved to the Trash"))
            } catch {
                core.showMessage(String(localized: "Couldn’t move it to the Trash"), tone: .danger)
            }
        }
    }
}

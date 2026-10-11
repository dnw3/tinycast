import AppKit

extension CaptureCoordinator {
    func copyHistoryFile(_ entry: CaptureHistoryEntry) async throws {
        let repository = repository
        let keeping = Set(PasteboardFiles.urls(on: .general))
        let url = try await CaptureWork.run { try repository.transfer(entry, now: Date(), keeping: keeping) }
        try writeCaptureFile(url)
        core.paletteCoordinator.hidePalette(restoreFocus: true)
    }

    func writeCaptureFile(_ url: URL) throws {
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL),
            item.setString(url.path, forType: .string),
            item.setString("capture", forType: ClipboardManager.internalType)
        else { throw CopyFailure.failed }
        core.clipboardManager.prepareForTinycastPasteboardMutation()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { throw CopyFailure.failed }
        core.clipboardManager.synchronizeAfterTinycastPasteboardMutation(
            changeCount: NSPasteboard.general.changeCount)
        core.showMessage(String(localized: "Copied capture file"), tone: .success)
    }

    func previewHistory(_ entry: CaptureHistoryEntry) async throws {
        let repository = repository
        let source = try await CaptureWork.run { try repository.openFile(entry, id: UUID()) }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        previewWindow.show(entry, source: source, metrics: metrics)
    }
}

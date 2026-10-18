import AppKit
import SwiftUI

extension CaptureCoordinator {
    func copy() { run { [weak self] in try await self?.copyCurrent() } }

    func copyCurrent(_ snapshotState: CaptureEditorState? = nil, close: Bool = true) async throws {
        guard let editor = snapshotState ?? editor else { return }
        editor.finishEditing()
        editor.busy = true
        defer { editor.busy = false }
        let snapshot = editor.document, source = editor.source
        let url = source.directory.appendingPathComponent("output-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try await CaptureWork.run {
            try CaptureRenderer.png(document: snapshot, directory: source.directory, to: url)
        }
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard CaptureCopyPolicy.accepts(encodedBytes: bytes) else { throw CopyFailure.budget }
        let data = try await CaptureWork.run { try Data(contentsOf: url) }
        try Task.checkCancellation()
        let item = NSPasteboardItem()
        guard item.setData(data, forType: .png),
            item.setString("capture", forType: ClipboardManager.internalType)
        else {
            throw CopyFailure.failed
        }
        core.clipboardManager.prepareForTinycastPasteboardMutation()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { throw CopyFailure.failed }
        core.clipboardManager.synchronizeAfterTinycastPasteboardMutation(
            changeCount: NSPasteboard.general.changeCount)
        core.clipboardManager.recordCapture(data, sourceBundleID: previousApp?.bundleIdentifier)
        editor.publishedRevision = snapshot.revision
        let recorded = await recordHistory(document: snapshot, source: source, png: url)
        core.showMessage(
            recorded != nil
                ? String(localized: "Copied screenshot")
                : String(localized: "Copied, but history couldn't be saved"),
            tone: recorded != nil ? .success : .neutral)
        if close, settings.preferences.closeAfterCopy, self.editor === editor,
            editor.document.revision == snapshot.revision
        {
            clearSelection()
            editorWindow.close()
            self.editor = nil
            restoreOtherResult()
            if video != nil { videoWindow.show(self) }
            restoreFocus()
            CapturePerformance.closed("copy-closed")
            CapturePerformance.closed()
        }
        if let recorded { completionThumbnail.show(recorded, coordinator: self) }
    }

    func saveAs(_ snapshotState: CaptureEditorState? = nil) {
        run { [weak self] in try await self?.saveAsCurrent(snapshotState) }
    }

    func saveAsCurrent(_ snapshotState: CaptureEditorState? = nil) async throws {
        guard let editor = snapshotState ?? self.editor, self.savePanel == nil, !editor.busy else { return }
        editor.finishEditing()
        let snapshot = editor.document, source = editor.source
        editor.busy = true
        self.overlay.suspend()
        let panel = NSSavePanel()
        defer {
            editor.busy = false
            panel.accessoryView = nil
            self.savePanel = nil
            self.overlay.resume()
        }
        panel.canCreateDirectories = true
        self.savePanel = panel
        var options = self.exportOptions
        if let format = CaptureExportOptions.Format(rawValue: self.settings.preferences.format),
            CaptureRenderer.exportFormats.contains(format)
        {
            options.format = format
        }
        let state = CaptureExportState(options: options, document: snapshot)
        panel.delegate = state
        let stem = "\(String(localized: "Screenshot"))-\(CaptureQuickSave.timestamp(Date()))"
        panel.nameFieldStringValue = "\(stem).\(options.format.rawValue)"
        state.update(panel)
        let controls = NSHostingView(
            rootView: CaptureExportControls(state: state, document: snapshot, panel: panel)
                .environment(\.metrics, self.metrics))
        controls.frame.size = controls.fittingSize
        panel.accessoryView = controls
        let response = await self.editorWindow.present(panel)
        self.savePanel = nil
        self.overlay.resume()
        guard response == .OK, let url = panel.url else { return }
        try Task.checkCancellation()
        let selected = state.options
        try await self.exportScreenshot(
            editor, snapshot: snapshot, source: source, to: url, options: selected)
        self.exportOptions = selected
        self.settings.preferences.format = selected.format.rawValue
    }

    func exportScreenshot(
        _ editor: CaptureEditorState, snapshot: CaptureDocument, source: CaptureSource,
        to url: URL, options: CaptureExportOptions, quickSave: CaptureQuickSave? = nil
    ) async throws {
        if options.format == .webp {
            try await CaptureWebPWorker.export(
                document: snapshot, directory: source.directory, to: url, options: options)
        } else {
            try await CaptureWork.run {
                try CaptureRenderer.export(
                    document: snapshot, directory: source.directory, to: url, options: options)
            }
        }
        if let quickSave { try await CaptureWork.run { try quickSave.publish() } }
        editor.publishedRevision = snapshot.revision
        let historyPNG = source.directory.appendingPathComponent("output-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: historyPNG) }
        let recorded: CaptureHistoryEntry?
        do {
            try await CaptureWork.run {
                try CaptureRenderer.png(document: snapshot, directory: source.directory, to: historyPNG)
            }
            recorded = await recordHistory(document: snapshot, source: source, png: historyPNG)
        } catch {
            recorded = nil
        }
        let destination = quickSave == nil ? url.deletingLastPathComponent() : quickSaveDirectory
        let path = (destination.path as NSString).abbreviatingWithTildeInPath
        core.showMessage(
            recorded != nil
                ? String(localized: "Saved to \(path)")
                : String(localized: "Saved, but history couldn't be saved"),
            tone: recorded != nil ? .success : .neutral)
        if let recorded { completionThumbnail.show(recorded, coordinator: self) }
    }

    func saveDraft() { run { [weak self] in try await self?.publishDraft() } }

    func publishDraft(_ state: CaptureEditorState? = nil) async throws {
        guard let editor = state ?? editor else { return }
        editor.finishEditing()
        editor.busy = true
        defer { editor.busy = false }
        let snapshot = editor.document, source = editor.source, repository = repository
        let url = source.directory.appendingPathComponent("draft-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try await CaptureWork.run {
            try CaptureRenderer.png(document: snapshot, directory: source.directory, to: url)
            try repository.commit(
                document: snapshot, directory: source.directory, png: url, editable: true, draft: true)
        }
        editor.publishedRevision = snapshot.revision
        core.showMessage(String(localized: "Saved editable draft"))
    }

    private func recordHistory(
        document: CaptureDocument, source: CaptureSource, png: URL
    ) async -> CaptureHistoryEntry? {
        let repository = repository, editable = settings.keepsOriginals, preferences = settings.preferences
        do {
            return try await CaptureWork.run {
                let entry = try repository.commit(
                    document: document, directory: source.directory, png: png, editable: editable,
                    draft: false)
                try repository.prune(
                    now: Date(), days: max(1, preferences.retentionDays),
                    maximumBytes: max(16, preferences.maximumHistoryMB) * 1_048_576)
                return entry
            }
        } catch {
            return nil
        }
    }

    func importClipboard(pin: Bool) async throws {
        let repository = repository, id = UUID(), raster = UUID().uuidString
        let source = try await CaptureWork.run { try CaptureSource(directory: try repository.create(id: id)) }
        let size = try await loadClipboardImage(at: source.directory.appendingPathComponent(raster))
        let document = CaptureDocument(
            id: id, createdAt: Date(), size: size,
            pieces: [
                .init(
                    raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                    origin: .zero)
            ])
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        if pin {
            try await self.pin(document: document, source: source)
        } else {
            show(document: document, source: source)
        }
    }

    func loadClipboardImage(at destination: URL) async throws -> CapturePixelSize {
        let pasteboard = NSPasteboard.general
        if let file = PasteboardFiles.urls(
            on: pasteboard, limit: 1,
            matching: {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
        ).first {
            return try await CaptureWork.run {
                try CaptureImageSource.load(file, at: destination)
            }
        } else if let type = pasteboard.availableType(from: [.png, .tiff]),
            let data = pasteboard.data(forType: type)
        {
            let input = destination.deletingLastPathComponent().appendingPathComponent("input-\(UUID())")
            return try await CaptureWork.run {
                try data.write(to: input)
                defer { try? FileManager.default.removeItem(at: input) }
                return try CaptureImageSource.load(input, at: destination)
            }
        } else {
            throw CopyFailure.noImage
        }
    }

    func openImage(_ url: URL, command: CommandID) {
        run { [weak self] in
            guard let self, await self.mayClose() else { return }
            let id = UUID(), raster = UUID().uuidString, repository = self.repository
            let result = try await CaptureWork.run {
                let source = try CaptureSource(directory: try repository.create(id: id))
                let size = try CaptureImageSource.load(
                    url, at: source.directory.appendingPathComponent(raster))
                return (
                    source,
                    CaptureDocument(
                        id: id, createdAt: Date(), size: size,
                        pieces: [
                            .init(
                                raster: raster,
                                source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                                origin: .zero)
                        ])
                )
            }
            self.core.paletteCoordinator.hidePalette(restoreFocus: false)
            if command == .pinClipboardImage {
                try await self.pin(document: result.1, source: result.0)
            } else {
                self.show(document: result.1, source: result.0)
                if command == .captureText || command == .captureAndTranslate {
                    try await self.recognizeCurrent(translate: command == .captureAndTranslate)
                }
            }
        }
    }

    enum CopyFailure: LocalizedError {
        case budget, failed, noImage
        var errorDescription: String? {
            switch self {
            case .budget:
                String(
                    localized:
                        "This PNG is too large for safe copying. Save it as PNG to keep the original resolution."
                )
            case .failed:
                String(localized: "The clipboard could not accept the image. Your screenshot is still open.")
            case .noImage: String(localized: "Copy an image or a local image file first.")
            }
        }
    }
}

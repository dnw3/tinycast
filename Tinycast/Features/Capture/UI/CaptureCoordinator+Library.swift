import AppKit

extension CaptureCoordinator {
    func pin() {
        run { [weak self] in
            guard let self, let editor = self.editor else { return }
            editor.finishEditing()
            guard self.pins.count < 3 else {
                editor.notice = "Close a pinned image first (maximum 3)"; return
            }
            editor.busy = true
            defer { editor.busy = false }
            try await self.pin(document: editor.document, source: editor.source)
            if self.workspace != nil {
                self.clearSelection()
                self.editor = nil
                self.restoreFocus()
            }
        }
    }

    func pin(document: CaptureDocument, source: CaptureSource) async throws {
        guard pins.count < 3 else {
            core.showMessage("Close a pinned image first (maximum 3)", tone: .neutral); return
        }
        let preview = try await CaptureWork.run {
            try CaptureRenderer.preview(document: document, directory: source.directory, maximum: 720)
        }
        let pin = CapturePinController(document: document, source: source)
        pins.append(pin)
        pin.show(preview: preview, coordinator: self)
    }

    func closePin(_ pin: CapturePinController) {
        pin.close()
        pins.removeAll { $0.id == pin.id }
        if pins.isEmpty { CapturePerformance.closed("pins-closed") }
    }

    func editPin(_ pin: CapturePinController) {
        run { [weak self] in
            guard let self, await self.mayClose() else { return }
            self.show(document: pin.document, source: pin.source)
        }
    }

    func copyPin(_ pin: CapturePinController) {
        run { [weak self] in
            guard let self else { return }
            try await self.copyCurrent(
                CaptureEditorState(document: pin.document, source: pin.source), close: false)
        }
    }

    func loadHistory() async throws {
        let repository = repository
        historyEntries = try await CaptureWork.run { try repository.entries() }
        core.paletteCoordinator.togglePalette(mode: .captureHistory)
    }

    func openHistory(_ entry: CaptureHistoryEntry, action: String = "edit") {
        run { [weak self] in
            guard let self else { return }
            self.previousApp = self.core.paletteCoordinator.targetApp
            if action == "share" {
                try await self.deliverFile(entry, via: .share, from: NSApp.keyWindow?.contentView)
                return
            }
            if action == "upload", let destination = self.settings.uploadDestination {
                let credential = try self.settings.uploadCredential(for: destination)
                try await self.deliverFile(entry, via: .upload(destination, credential), from: nil)
                return
            }
            if action == "preview" || entry.animationDuration != nil && action == "edit" {
                try await self.previewHistory(entry)
                return
            }
            if action == "copyFile" || action == "copy" && (entry.videoDuration != nil || entry.animationDuration != nil) {
                try await self.copyHistoryFile(entry)
                return
            }
            if action == "edit", !(await self.mayClose()) { return }
            if entry.videoDuration != nil {
                try await self.openVideoHistory(entry)
                return
            }
            let repository = self.repository, id = UUID()
            let result = try await CaptureWork.run {
                let (document, directory) = try repository.open(entry, id: id)
                return (document, try CaptureSource(directory: directory))
            }
            self.core.paletteCoordinator.hidePalette(restoreFocus: false)
            if action == "pin" {
                try await self.pin(document: result.0, source: result.1)
            } else if action == "copy" {
                try await self.copyCurrent(
                    CaptureEditorState(document: result.0, source: result.1), close: false)
            } else {
                self.show(document: result.0, source: result.1)
                self.editor?.publishedRevision = result.0.revision
            }
        }
    }

    func revealHistory(_ entry: CaptureHistoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([
            repository.history.appendingPathComponent(entry.id.uuidString).appendingPathComponent(entry.filename)
        ])
    }

    func deleteHistory(_ entry: CaptureHistoryEntry) {
        run { [weak self] in
            guard let self,
                await self.core.confirm(
                    title: "Delete Capture?",
                    message: "This removes the saved capture and its editable draft, if any.",
                    symbol: "trash", confirmTitle: "Delete")
            else { return }
            let url = self.repository.history.appendingPathComponent(entry.id.uuidString)
            try await CaptureWork.run { try FileManager.default.removeItem(at: url) }
            self.historyEntries.removeAll { $0.id == entry.id }
        }
    }
}

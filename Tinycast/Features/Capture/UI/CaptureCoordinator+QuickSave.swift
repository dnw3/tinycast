import AppKit

extension CaptureCoordinator {
    var quickSaveDirectory: URL {
        if let folder = core.settings.captureQuickSaveFolder {
            return URL(filePath: (folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tinycast")
    }

    func revealQuickSaveFolder() {
        let directory = quickSaveDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else {
            core.showMessage(
                String(localized: "Quick Save creates \(directory.path) when you first save"), tone: .neutral)
            return
        }
        if workspace != nil { expandCapture() }
        NSWorkspace.shared.open(directory)
    }

    func resetQuickSaveFolder() { core.settings.captureQuickSaveFolder = nil }

    func chooseQuickSaveFolder() {
        run { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = self.quickSaveDirectory
            panel.prompt = "Choose"
            self.savePanel = panel
            self.overlay.suspend()
            defer { self.savePanel = nil; self.overlay.resume() }
            let response = await self.editorWindow.present(panel)
            try Task.checkCancellation()
            guard response == .OK, let url = panel.url else { return }
            self.core.settings.captureQuickSaveFolder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    func save(_ snapshotState: CaptureEditorState? = nil) {
        run { [weak self] in
            guard let self, let editor = snapshotState ?? self.editor else { return }
            editor.finishEditing()
            editor.busy = true
            defer { editor.busy = false }
            let snapshot = editor.document, source = editor.source, workspace = self.workspace
            let directory = self.quickSaveDirectory,
                createDirectory = self.core.settings.captureQuickSaveFolder == nil
            var options = self.exportOptions
            if let format = CaptureExportOptions.Format(rawValue: self.settings.preferences.format),
                CaptureRenderer.exportFormats.contains(format)
            {
                options.format = format
            }
            let selected = options
            let output = try await CaptureWork.run {
                try CaptureQuickSave(
                    directory: directory, createDirectory: createDirectory,
                    format: selected.format, now: Date())
            }
            defer { output.discard() }
            try await self.exportScreenshot(
                editor, snapshot: snapshot, source: source,
                to: output.staging, options: selected, quickSave: output)
            try Task.checkCancellation()
            guard let workspace, self.workspace === workspace, self.editor === editor,
                self.pendingCapture == nil, editor.document.revision == snapshot.revision
            else { return }
            self.clearSelection()
            self.editor = nil
            self.restoreOtherResult()
            if self.video != nil { self.videoWindow.show(self) }
            self.restoreFocus()
            CapturePerformance.closed("save-closed")
            CapturePerformance.closed()
        }
    }
}
